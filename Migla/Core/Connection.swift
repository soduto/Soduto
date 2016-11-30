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
    func connection(_ connection:Connection, didSendPacket:DataPacket, uploadedPayload: Bool)
    func connection(_ connection:Connection, didReadPacket:DataPacket)
}

public protocol ConnectionConfiguration: HostConfiguration {
    var hostCertificate: SecIdentity? { get }
    func deviceConfig(for deviceId:Device.Id) -> DeviceConfiguration
}

public protocol ConnectionDataPacketHandler {
    func handleDataPacket(_ dataPacket:DataPacket, onConnection connection:Connection) -> Bool
}

public class Connection: NSObject, GCDAsyncSocketDelegate, PairingHandlerDelegate, Pairable, PairableDelegate, UploadTaskDelegate {
    
    // MARK: Types
    
    public enum ConnectionError: Error {
        case setSocketOptionFailed(code: Int32)
    }
    
    public enum State {
        case Initializing
        case Open
        case Closed
    }
    
    public typealias SendingCompletionHandler = ((_ packetSent: Bool, _ payloadSent: Bool) -> Void)
    
    private struct DataPacketSendingInfo {
        
        let dataPacket: DataPacket
        let uploadTask: UploadTask?
        let completionHandler: SendingCompletionHandler?
        var packetSent: Bool? = nil
        var payloadSent: Bool? = nil
        
        init(dataPacket: DataPacket, uploadTask: UploadTask?, completionHandler: SendingCompletionHandler?) {
            self.dataPacket = dataPacket
            self.uploadTask = uploadTask
            self.completionHandler = completionHandler
            if self.uploadTask == nil {
                self.payloadSent = false
            }
        }
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
    private let uploadQueue = DispatchQueue(label: "Payload upload queue", qos: DispatchQoS.background, autoreleaseFrequency: .workItem)
    private var packetsToSend: [DataPacketSendingInfo] = [] // queue of packets waiting to be sent
    private var packetsExpected: Int = 0         // count of packets to read befor stopping automatic reading, -1 for unlimited count
    private var waitingToSecure: Bool = false
    private var shouldFinishIntializationWhenSecured: Bool = false
    private var pairingHandler: DefaultPairingHandler? = nil
    private var packetHandlers: [ConnectionDataPacketHandler] = []
    
    static private let packetsDelimiter: Data = Data(bytes: [UInt8(ascii: "\n")])
    
    
    // MARK: Initialization / Deinitialization
    
    init?(address: SocketAddress, identityPacket packet: DataPacket, config: ConnectionConfiguration) {
        guard let hostIdentity = config.hostCertificate else { return nil }
        
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
//        self.configureSocket()
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
        self.configureSocket()
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
    
    public func secureServer() {
        assert(self.state == .Initializing, "Connection initialization already finished")
        assert(self.identity != nil, "Identity expected to be known before securing connection")
        
        self.secureServerSocket(self.socket)
        self.waitingToSecure = true
    }
    
    public func secureClient() {
        assert(self.state == .Initializing, "Connection initialization already finished")
        assert(self.identity != nil, "Identity expected to be known before securing connection")
        
        self.secureClientSocket(self.socket)
        self.waitingToSecure = true
    }
    
    public func finishInitialization() {
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
    
    public func send(_ dataPacket: DataPacket, whenCompleted: SendingCompletionHandler? = nil) {
        var packet = dataPacket
        
        let uploadTask: UploadTask?
        if packet.hasPayload() {
            uploadTask = UploadTask(packet: packet, connection: self, readQueue: self.uploadQueue)
            uploadTask?.delegate = self
            packet.payloadInfo = uploadTask?.payloadInfo
        }
        else {
            uploadTask = nil
        }
        
        if let bytes = try? packet.serialize() {
            let data = Data(bytes: bytes)
            self.socket.write(data, withTimeout: -1, tag: Int(packet.id))
        }
        
        let info = DataPacketSendingInfo(dataPacket: packet, uploadTask: uploadTask, completionHandler: whenCompleted)
        self.packetsToSend.append(info)
    }
    
    public func send(_ packet: DataPacket) {
        self.send(packet, whenCompleted: nil)
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
    
    /// Helper function to secure any server socket equivalently as this connection secures
    /// its own socket - with same certificates and settings
    public func secureServerSocket(_ socket: GCDAsyncSocket) {
        let settings: [String:NSObject] = [
            kCFStreamSSLCertificates as String: self.sslCertificates as NSArray,
            kCFStreamSSLIsServer as String: NSNumber(value: true),
            GCDAsyncSocketSSLClientSideAuthenticate as String: NSNumber(value: SSLAuthenticate.alwaysAuthenticate.rawValue),
            GCDAsyncSocketManuallyEvaluateTrust as String: NSNumber(value: true)
        ]
        socket.startTLS(settings)
    }
    
    /// Helper function to secure any client socket equivalently as this connection secures
    /// its own socket - with same certificates and settings
    public func secureClientSocket(_ socket: GCDAsyncSocket) {
        let settings: [String:NSObject] = [
            kCFStreamSSLCertificates as String: self.sslCertificates as NSArray,
            GCDAsyncSocketManuallyEvaluateTrust as String: NSNumber(value: true)
        ]
        self.socket.startTLS(settings)
    }
    
    /// Helper function to validate peer certificate equivalently as this connection validates
    /// its own connections
    public func shouldTrustPeerCertificate(_ peerCertificate: SecCertificate) -> Bool {
        assert(self.identity != nil, "Identity expected to be known before securing connection and evaluating trust")
        
        guard let deviceId = try? self.identity!.getDeviceId() else { return false }
        guard let savedCertificate = self.config.deviceConfig(for: deviceId).certificate else { return false }
        return CertificateUtils.compareCertificates(savedCertificate, peerCertificate)
    }
    
    
    // MARK: GCDAsyncSocketDelegate
    
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        Swift.print("Connection.socket:didConnectToHost:port: \(sock) \(host) \(port)")
    }
    
    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        Swift.print("Connection.socket:didWriteDataWithTag: \(sock) \(tag)")
        
        let indexOpt = self.packetsToSend.index { packetInfo -> Bool in
            return Int(packetInfo.dataPacket.id) == tag
        }
        guard let index = indexOpt else { return }
        
        self.packetsToSend[index].packetSent = true
        
        if let payloadSent = self.packetsToSend[index].payloadSent {
            let packetInfo = self.packetsToSend.remove(at: index)
            if let completionHandler = packetInfo.completionHandler {
                completionHandler(true, payloadSent)
            }
            self.delegate?.connection(self, didSendPacket: packetInfo.dataPacket, uploadedPayload: payloadSent)
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
    
    
    // MARK: UploadTaskDelegate
    
    public func uploadTask(_ task: UploadTask, finishedWithSuccess payloadSent: Bool) {
        Swift.print("Connction.uploadTask:finishedWithSuccess: \(task) \(payloadSent)")
        
        guard let index = self.packetsToSend.index(where: { $0.uploadTask === task }) else { return }
        
        self.packetsToSend[index].payloadSent = true
        
        assert(self.packetsToSend[index].packetSent == true, "Payload expected to be uploaded after packet is sent (since payload info is in the packet)")
        guard let packetSent = self.packetsToSend[index].packetSent else { return }
        guard packetSent == true else { return }
        
        let packetInfo = self.packetsToSend.remove(at: index)
        if let completionHandler = packetInfo.completionHandler {
            completionHandler(true, payloadSent)
        }
        self.delegate?.connection(self, didSendPacket: packetInfo.dataPacket, uploadedPayload: payloadSent)
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
    
    private func configureSocket() {
        self.socket.perform {
            if self.socket.isIPv4 {
                do {
                    let nativeSocket = self.socket.socket4FD()
                    try self.setSockOpt(socket: nativeSocket, level: SOL_SOCKET, optionName: SO_KEEPALIVE, optionValue: 1)
                    try self.setSockOpt(socket: nativeSocket, level: IPPROTO_TCP, optionName: TCP_KEEPALIVE, optionValue: 10)
                }
                catch {
                    Swift.print("Failed to configure socket for connection \(self): \(error)")
                }
            }
            
            if self.socket.isIPv6 {
                do {
                    let nativeSocket = self.socket.socket6FD()
                    try self.setSockOpt(socket: nativeSocket, level: SOL_SOCKET, optionName: SO_KEEPALIVE, optionValue: 1)
                    try self.setSockOpt(socket: nativeSocket, level: IPPROTO_TCP, optionName: TCP_KEEPALIVE, optionValue: 10)
                }
                catch {
                    Swift.print("Failed to configure socket for connection \(self): \(error)")
                }
            }
        }
    }
    
    private func setSockOpt(socket: Int32, level: Int32, optionName: Int32, optionValue: Int32) throws {
        var value = optionValue // need writable value
        let result = setsockopt(socket, level, optionName, &value, UInt32(MemoryLayout<Int32>.size))
        if result != 0 {
            throw ConnectionError.setSocketOptionFailed(code: errno)
        }
    }
    
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
            return self.shouldTrustPeerCertificate(peerCertificate)
        }
        else {
            return true
        }
    }

}
