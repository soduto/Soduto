//
//  Connection.swift
//  Migla
//
//  Created by Admin on 2016-08-04.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import CocoaAsyncSocket

public enum ConnectionError: Error {
    case InitializationAlreadyFinished
    case IdentityAbsent
}

public protocol ConnectionDelegate: class {
    func connection(_ connection:Connection, didSwitchToState:Connection.State)
    func connection(_ connection:Connection, didSendPacket:DataPacket)
    func connection(_ connection:Connection, didReadPacket:DataPacket)
}

public protocol ConnectionConfiguration: HostConfiguration {
    var hostCertificate: SecIdentity? { get }
    func deviceConfig(for deviceId:Device.Id) -> DeviceConfiguration
}

public class Connection: NSObject, GCDAsyncSocketDelegate, PairingHandlerDelegate, Pairable, PairableDelegate {
    
    // MARK: Types
    
    public enum State {
        case Initializing
        case Open
        case Closed
    }
    
    
    // MARK: Properties
    
    public weak var delegate: ConnectionDelegate?
    
    public weak var pairingDelegate: PairableDelegate?
    
    public private(set) var state: State {
        didSet {
            if oldValue != self.state {
                self.delegate?.connection(self, didSwitchToState: self.state)
            }
        }
    }
    
    public private(set) var identity: DataPacket? = nil
    public private(set) var peerCertificate: SecCertificate? = nil
    
    private let config: ConnectionConfiguration
    private let socket: GCDAsyncSocket
    private let sslCertificates: [AnyObject]
    private var packetsToSend: [DataPacket] = [] // queue of packets waiting to be sent
    private var packetsExpected: Int = 0         // count of packets to read befor stopping automatic reading, -1 for unlimited count
    private var waitingToSecure: Bool = false
    private var shouldFinishIntializationWhenSecured: Bool = false
    private var pairingHandler: DefaultPairingHandler? = nil
    private var packetHandlers: [DataPacketsHandler] = []
    
    static private let packetsDelimiter: Data = Data(bytes: [UInt8(ascii: "\n")])
    
    
    // MARK: Initialization / Deinitialization
    
    init?(address: SocketAddress, identityPacket packet: DataPacket, config: ConnectionConfiguration) {
        guard let hostIdentity = config.hostCertificate else { return nil }
        
        setenv("CFNETWORK_DIAGNOSTICS", "3", 1);
        
        self.config = config
        self.socket = GCDAsyncSocket(delegate: nil, delegateQueue: DispatchQueue.main)
        self.sslCertificates = [ hostIdentity ]
        self.state = .Initializing

        super.init()
        
        self.socket.delegate = self
        do {
            try self.applyIdentity(packet: packet)
            try self.socket.connect(toAddress: address.data)
        }
        catch {
            Swift.print("Could not connect to address \(address): \(error)")
            return nil
        }
    }
    
    init?(socket: GCDAsyncSocket, config: ConnectionConfiguration) {
        guard socket.isConnected else { return nil }
        guard let hostIdentity = config.hostCertificate else { return nil }
        
        self.config = config
        self.socket = socket
        self.sslCertificates = [ hostIdentity ]
        self.state = .Initializing
        
        super.init()
        
        self.socket.delegate = self
    }
    
    deinit {
        self.close()
    }
    
    public func applyIdentity(packet: DataPacket) throws {
        assert(self.state == .Initializing, "Connection initialization already finished")
        
        try packet.validateIdentityType()
        let deviceId = try packet.getDeviceId()
        let deviceConfig = self.config.deviceConfig(for: deviceId)
        
        self.identity = packet
        self.pairingHandler = DefaultPairingHandler(config: deviceConfig)
        self.pairingHandler!.delegate = self
        self.pairingHandler!.pairingDelegate = self
        self.packetHandlers.append(self.pairingHandler!)
    }
    
    public func secureServer() throws {
        assert(self.state == .Initializing, "Connection initialization already finished")
        assert(self.identity != nil, "Identity expected to be known before securing connection")
        
        let settings: [String:NSObject] = [
            kCFStreamSSLCertificates as String: self.sslCertificates as NSArray,
            kCFStreamSSLIsServer as String: NSNumber(value: true),
            GCDAsyncSocketManuallyEvaluateTrust as String: NSNumber(value: true)
        ]
        self.socket.startTLS(settings)
        self.waitingToSecure = true
    }
    
    public func secureClient() throws {
        assert(self.state == .Initializing, "Connection initialization already finished")
        assert(self.identity != nil, "Identity expected to be known before securing connection")
        
        let settings: [String:NSObject] = [
            kCFStreamSSLCertificates as String: self.sslCertificates as NSArray,
            GCDAsyncSocketManuallyEvaluateTrust as String: NSNumber(value: true)
        ]
        self.socket.startTLS(settings)
        self.waitingToSecure = true
    }
    
    public func finishInitialization() throws {
        assert(self.state == .Initializing, "Connection initialization already finished")
        assert(self.identity != nil, "Connection identity must be set before finishing initialization")
        
        if !self.waitingToSecure {
            self.state = .Open
        }
        else {
            self.shouldFinishIntializationWhenSecured = true
        }
    }
    
    
    // MARK: Public API
    
    public func send(_ packet:DataPacket) {
        self.packetsToSend.append(packet)
        if let bytes = try? packet.serialize() {
            let data = Data(bytes: bytes)
            self.socket.write(data, withTimeout: -1, tag: Int(packet.id))
        }
    }
    
    public func readOnePacket() {
        self.packetsExpected = 1
        self.readNextPacket()
    }
    
    public func readPackets() {
        self.packetsExpected = -1
        self.readNextPacket()
    }
    
    public func close() {
        self.socket.disconnect()
        self.state = .Closed
    }
    
    
    // MARK: GCDAsyncSocketDelegate
    
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        Swift.print("Connection.socket:didConnectToHost:port: \(sock) \(host) \(port)")
    }
    
    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        Swift.print("Connection.socket:didWriteDataWithTag: \(sock) \(tag)")
        
        let indexOpt = self.packetsToSend.index { packet -> Bool in
            return Int(packet.id) == tag
        }
        if let index = indexOpt {
            let packet = self.packetsToSend.remove(at: index)
            self.delegate?.connection(self, didSendPacket: packet)
        }
    }
    
    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        Swift.print("Connection.socket:didRead:withTag: \(sock) \(data) \(tag)")
        
        if data.count > 0 {
            if let packet = DataPacket(data: data) {
                self.handle(packet: packet)
                if self.packetsExpected > 0 {
                    self.packetsExpected = self.packetsExpected - 1
                }
            }
            else {
                Swift.print("Could not deserialize DataPacket")
            }
        }
    
        if self.packetsExpected != 0 {
            self.readNextPacket()
        }
    }
    
    public func socketDidSecure(_ sock: GCDAsyncSocket) {
        Swift.print("Connection.socketDidSecure: \(sock)")
        self.waitingToSecure = false
        if self.shouldFinishIntializationWhenSecured {
            self.state = .Open
        }
    }
    
    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        Swift.print("Connection.socketDidDisconnect:withError: \(sock) \(err)")
        self.close()
    }
    
    public func socket(_ sock: GCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void) {
        completionHandler(self.shouldTrustPeer(trust))
    }
    
    
    // MARK: PairableDelegate
    
    public func pairable(_ pairable:Pairable, receivedRequest request:PairingRequest) {
        self.pairingDelegate?.pairable(self, receivedRequest:request)
    }
    
    public func pairable(_ pairable:Pairable, failedWithError error:Error) {
        self.pairingDelegate?.pairable(self, failedWithError:error)
    }
    
    public func pairable(_ pairable:Pairable, statusChanged status:PairingStatus) {
        self.pairingDelegate?.pairable(self, statusChanged: status)
    }
    
    
    // MARK: Pairable
    
    public var pairingStatus: PairingStatus {
        if self.state == .Open {
            return self.pairingHandler!.pairingStatus
        }
        else {
            return .Unpaired
        }
    }
    
    public func requestPairing() {
        assert(self.state == .Open, "Connection expected to be open")
        self.pairingHandler!.requestPairing()
    }
    
    public func acceptPairing() {
        assert(self.state == .Open, "Connection expected to be open")
        self.pairingHandler!.acceptPairing()
    }
    
    public func declinePairing() {
        assert(self.state == .Open, "Connection expected to be open")
        self.pairingHandler!.declinePairing()
    }
    
    public func unpair() {
        assert(self.state == .Open, "Connection expected to be open")
        self.pairingHandler!.unpair()
    }
    
    public func updatePairingStatus(globalStatus: PairingStatus) {
        assert(self.state == .Open, "Connection expected to be open")
        self.pairingHandler!.updatePairingStatus(globalStatus: globalStatus)
    }

    
    // MARK: Private
    
    private func readNextPacket() {
        self.socket.readData(to: Connection.packetsDelimiter, withTimeout: -1, tag: 0)
    }
    
    private func handle(packet: DataPacket) {
        // try to handle with registered handlers
        for handler in self.packetHandlers {
            let handled = handler.handleDataPacket(packet, onConnection: self)
            if handled {
                return
            }
        }
        
        // if not handled - pass to delegate
        self.delegate?.connection(self, didReadPacket: packet)
    }
    
    private func shouldTrustPeer(_ trust: SecTrust) -> Bool {
        assert(self.identity != nil, "Identity expected to be known before securing connection and evaluating trust")
        
        guard let peerCertificate = SecTrustGetCertificateAtIndex(trust, 0) else { return false }
        self.peerCertificate = peerCertificate
        
        if self.pairingStatus == .Paired {
            guard let deviceId = try? self.identity!.getDeviceId() else { return false }
            guard let savedCertificate = self.config.deviceConfig(for: deviceId).certificate else { return false }
            return CertificateUtils.compareCertificates(savedCertificate, peerCertificate)
        }
        else {
            return true
        }
    }

}
