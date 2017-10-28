//
//  Connection.swift
//  Soduto
//
//  Created by Admin on 2016-08-04.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import CocoaAsyncSocket
import CleanroomLogger
import Reachability

public enum ConnectionError: Error {
    case InitializationAlreadyFinished
    case IdentityAbsent
}

public protocol ConnectionDelegate: class {
    func connection(_ connection:Connection, didSwitchToState:Connection.State)
    func connection(_ connection:Connection, didSendPacket:DataPacket, uploadedPayload: Bool)
    func connection(_ connection:Connection, didReadPacket:DataPacket)
    func connectionCapacityChanged(_ connection:Connection) // Informs receiver that it can try to resend previously declined packets
}

public protocol ConnectionConfiguration: HostConfiguration {
    var hostCertificate: SecIdentity? { get }
    func deviceConfig(for deviceId:Device.Id) -> DeviceConfiguration
    func knownDeviceConfigs() -> [DeviceConfiguration]
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
    
    public struct DataPacketSendingInfo {
        
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
            
            if self.state == .Open && self.pairingStatus == .Paired {
                self.rememberHwAddress()
            }
        }
    }
    
    public private(set) var identity: DataPacket? = nil
    public private(set) var peerCertificate: SecCertificate? = nil
    public private(set) var peerAddress: SocketAddress
    
    public var hostCertificate: SecCertificate? { return self.config.hostCertificate?.certificate }
    
    private let config: ConnectionConfiguration
    private let socket: GCDAsyncSocket
    private let sslCertificates: [AnyObject]
    private let uploadQueue = Connection.createDispatchQueue(withLabel: "Payload upload queue")
    private let downloadQueue = Connection.createDispatchQueue(withLabel: "Payload download queue")
    private var packetsSending: [DataPacketSendingInfo] = []  // array of packets being sent
    private var packetsExpected: Int = 0         // count of packets to read befor stopping automatic reading, -1 for unlimited count
    private var waitingToSecure: Bool = false
    private var shouldFinishIntializationWhenSecured: Bool = false
    private var pairingHandler: DefaultPairingHandler? = nil
    private var packetHandlers: [ConnectionDataPacketHandler] = []
    
    static private let packetsDelimiter: Data = Data(bytes: [UInt8(ascii: "\n")])
    
    
    // MARK: Initialization / Deinitialization
    
    init?(address: SocketAddress, identityPacket packet: DataPacket, config: ConnectionConfiguration) {
        guard let hostIdentity = config.hostCertificate else { return nil }
        
        self.peerAddress = address
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
            Log.error?.message("Could not connect to address \(address): \(error)")
            return nil
        }
        self.configureSocket()
    }
    
    init?(socket: GCDAsyncSocket, config: ConnectionConfiguration) {
        guard socket.isConnected else { return nil }
        guard let connectedAddress = socket.connectedAddress else { return nil }
        guard let hostIdentity = config.hostCertificate else { return nil }
        
        self.peerAddress = SocketAddress(data: connectedAddress)
        self.config = config
        self.socket = socket
        self.sslCertificates = [ hostIdentity ]
        self.state = .Initializing
        
        super.init()
        
        self.socket.delegate = self
        self.configureSocket()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        self.state = .Closed
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
        
        self.observeNotifications()
    }
    
    
    // MARK: Public API
    
    /// Try sending a packed with completion handler. Returns false if sending is declined because of capacity exceeded.
    /// In such case the sender may try resending the packet when connection capacity changes. In other cases 
    /// true is returned even if sending does not succeed - sending failure is reported through completion handler.
    public func send(_ dataPacket: DataPacket, whenCompleted: SendingCompletionHandler? = nil) -> Bool {
        if dataPacket.hasPayload() {
            return self.sendPayloadPacket(dataPacket, whenCompleted: whenCompleted)
        }
        else {
            return self.sendSimplePacket(dataPacket, whenCompleted: whenCompleted)
        }
    }
    
    public func send(_ dataPacket: DataPacket) -> Bool {
        return self.send(dataPacket, whenCompleted: nil)
    }
    
    public func readOnePacket() {
        self.packetsExpected = 1
        self.readNextPacket()
    }
    
    public func readPackets() {
        self.packetsExpected = -1
        self.readNextPacket()
    }
    
    /// Discard and return unsent packets, so that they can be resent with other connection. This can be done only when 
    /// connection is already closed, otherwise behaviour is undefined
    public func reclaimUnsentPackets() -> [(dataPacket: DataPacket, completionHandler: SendingCompletionHandler?)] {
        assert(self.state == .Closed)
        return self.discardUnsentPackets(silently: true)
    }
    
    /// Disconnect underlying socket, effectively discarded all unfinished packet writings. State change however is not
    /// performed imediately, but in the near future when diconnect event is received
    public func close() {
        self.socket.disconnect()
    }
    
    /// Wait for all packet writes are finished and then discard. State change however is not
    /// performed imediately, but in the near future when diconnect event is received
    public func closeAfterWriting() {
        self.socket.disconnectAfterWriting()
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
        socket.startTLS(settings)
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
        Log.debug?.message("socket(<\(sock)> didConnectToHost:<\(host)> port:<\(port)>)")
    }
    
    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        Log.debug?.message("socket(<\(sock)> didWriteDataWithTag:<\(tag)>)")
        
        assert(self.packetsSending.index(where: { Int($0.dataPacket.id) == tag }) != nil, "Data packet is not in the packetsSending list.")
        guard let index = self.packetsSending.index(where: { Int($0.dataPacket.id) == tag }) else { return }
        
        self.packetsSending[index].packetSent = true
        
        if let payloadSent = self.packetsSending[index].payloadSent {
            let packetInfo = self.packetsSending.remove(at: index)
            self.finalizeSending(packet: packetInfo.dataPacket, completionHandler: packetInfo.completionHandler, packetSent: true, payloadSent: payloadSent)
        }
    }
    
    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        Log.debug?.message("socket(<\(sock)> didRead:<\(data)> withTag:<\(tag)>)")
        
        if data.count > 0 {
            if let packet = DataPacket(data: data) {
                var mutablePacket = packet
                if mutablePacket.payloadInfo != nil {
                    mutablePacket.downloadTask = DownloadTask(packet: mutablePacket, connection: self, writeQueue: self.downloadQueue)
                }
                
                self.handle(packet: mutablePacket)
                if self.packetsExpected > 0 {
                    self.packetsExpected = self.packetsExpected - 1
                }
            }
            else {
                Log.error?.message("Could not deserialize received data packet")
            }
        }
    
        if self.packetsExpected != 0 {
            self.readNextPacket()
        }
    }
    
    public func socketDidSecure(_ sock: GCDAsyncSocket) {
        Log.debug?.message("socketDidSecure(<\(sock)>)")
        self.waitingToSecure = false
        if self.shouldFinishIntializationWhenSecured {
            self.state = .Open
        }
    }
    
    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        Log.debug?.message("socketDidDisconnect(<\(sock)> withError:<\(String(describing: err))>)")
    
        // Execute state change before packets dicarding, so that delegate could reclaim unsent packets
        self.state = .Closed
        
        // Discard unsent packets, leaving only those packets that have uploads in progress.
        _ = self.discardUnsentPackets(silently: true)
    }
    
    public func socket(_ sock: GCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void) {
        completionHandler(self.shouldTrustPeer(trust))
    }
    
    
    // MARK: UploadTaskDelegate
    
    public func uploadTask(_ task: UploadTask, finishedWithSuccess payloadSent: Bool) {
        Log.debug?.message("uploadTask(<\(task)> finishedWithSuccess:<\(payloadSent)>)")
        
        assert(self.packetsSending.index(where: { $0.uploadTask === task }) != nil, "Data packet is not in the packetsSending list.")
        guard let index = self.packetsSending.index(where: { $0.uploadTask === task }) else { return }
        
        self.packetsSending[index].payloadSent = true
        
//        assert(self.packetsSending[index].packetSent == true, "Payload expected to be uploaded after packet is sent (since payload info is in the packet)")
        if let packetSent = self.packetsSending[index].packetSent {
            let packetInfo = self.packetsSending.remove(at: index)
            self.finalizeSending(packet: packetInfo.dataPacket, completionHandler: packetInfo.completionHandler, packetSent: packetSent, payloadSent: payloadSent)
        }
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
        
        if self.pairingStatus == .Paired {
            self.rememberHwAddress()
        }
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

    
    // MARK: CustomStringConvertible
    
    public override var description: String {
        // Extract socket address string
        let socketString = self.socket.description
        let endIndex = socketString.index(socketString.endIndex, offsetBy: -1)
        let startIndex = socketString.index(endIndex, offsetBy: -11)
        let socketAddress = socketString[startIndex..<endIndex]
        
        let id: String = (try? self.identity?.getDeviceId() ?? "") ?? ""
        let name: String = (try? self.identity?.getDeviceName() ?? "") ?? ""
        return "<Connection:\(socketAddress):\(id):\(name)>"
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
                    Log.error?.message("Failed to configure socket for connection \(self): \(error)")
                }
            }
            
            if self.socket.isIPv6 {
                do {
                    let nativeSocket = self.socket.socket6FD()
                    try self.setSockOpt(socket: nativeSocket, level: SOL_SOCKET, optionName: SO_KEEPALIVE, optionValue: 1)
                    try self.setSockOpt(socket: nativeSocket, level: IPPROTO_TCP, optionName: TCP_KEEPALIVE, optionValue: 10)
                }
                catch {
                    Log.error?.message("Failed to configure socket for connection \(self): \(error)")
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
    
    private func sendSimplePacket(_ packet: DataPacket, whenCompleted: SendingCompletionHandler? = nil) -> Bool {
        assert(!packet.hasPayload())
        
        Log.debug?.message("send(:\(packet) whenCompleted:\(String(describing: whenCompleted))) [\(self)]")
        
        if let bytes = try? packet.serialize() {
            let data = Data(bytes: bytes)
            self.socket.write(data, withTimeout: -1, tag: Int(packet.id))
            let info = DataPacketSendingInfo(dataPacket: packet, uploadTask: nil, completionHandler: whenCompleted)
            self.packetsSending.append(info)
        }
        else {
            Log.error?.message("Failed to serialize packet: \(packet).")
            self.finalizeSending(packet: packet, completionHandler: whenCompleted, packetSent: false, payloadSent: false)
        }
        
        return true
    }
    
    private func sendPayloadPacket(_ packet: DataPacket, whenCompleted: SendingCompletionHandler? = nil) -> Bool {
        assert(packet.hasPayload())
        
        if let uploadTask = UploadTask(packet: packet, connection: self, readQueue: self.uploadQueue) {
            
            Log.debug?.message("send(:\(packet) whenCompleted:\(String(describing: whenCompleted))) [\(self)]")
            
            var packet = packet
            packet.payloadInfo = uploadTask.payloadInfo
            uploadTask.delegate = self
            
            if let bytes = try? packet.serialize() {
                let data = Data(bytes: bytes)
                self.socket.write(data, withTimeout: -1, tag: Int(packet.id))
                let info = DataPacketSendingInfo(dataPacket: packet, uploadTask: uploadTask, completionHandler: whenCompleted)
                self.packetsSending.append(info)
            }
            else {
                Log.error?.message("Failed to serialize packet: \(packet).")
                self.finalizeSending(packet: packet, completionHandler: whenCompleted, packetSent: false, payloadSent: false)
            }
            return true
        }
        else if !UploadTask.hasUsedPorts() {
            // We dont have any ports in use, so no will become available and no point of waiting - fail immediately
            Log.error?.message("Failed to initialize upload task for packet \(packet).")
            self.finalizeSending(packet: packet, completionHandler: whenCompleted, packetSent: false, payloadSent: false)
            return true
        }
        else {
            // Tell caller to wait
            return false
        }
    }
    
    private func sendKeepAlivePacket() {
        let packet = DataPacket(type: "soduto.keepalive", body: [:])
        _ = send(packet)
    }
    
    private func finalizeSending(packet: DataPacket, completionHandler: SendingCompletionHandler?, packetSent: Bool, payloadSent: Bool) {
        completionHandler?(packetSent, payloadSent)
        if packetSent {
            self.delegate?.connection(self, didSendPacket: packet, uploadedPayload: payloadSent)
        }
    }
    
    private func readNextPacket() {
        self.socket.readData(to: Connection.packetsDelimiter, withTimeout: -1, tag: 0)
    }
    
    private func handle(packet: DataPacket) {
        Log.debug?.message("handle(packet: <\(packet)>) [\(self)]")
        
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
        
        if self.pairingHandler!.pairingStatus == .Paired {
            return self.shouldTrustPeerCertificate(peerCertificate)
        }
        else {
            return true
        }
    }
    
    private func rememberHwAddress() {
        guard self.pairingStatus == .Paired else { return }
        guard let deviceId = (try? self.identity?.getDeviceId()) ?? nil else { return }
        guard let hwAddress = NetworkUtils.hwAddress(for: self.peerAddress) else { return }
        
        self.config.deviceConfig(for: deviceId).addHwAddress(hwAddress)
    }
    
    private func observeNotifications() {
        NotificationCenter.default.addObserver(forName: UploadTask.portReleaseNotification, object: nil, queue: nil) { [weak self] notification in
            if let strongSelf = self {
                strongSelf.delegate?.connectionCapacityChanged(strongSelf)
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name.reachabilityChanged, object: nil, queue: nil) { [weak self] notification in
            if let reachability = notification.object as? Reachability, reachability.connection != .none {
                self?.sendKeepAlivePacket()
            }
        }
    }
    
    private func discardUnsentPackets(silently: Bool) -> [(dataPacket: DataPacket, completionHandler: SendingCompletionHandler?)] {
        var results: [(dataPacket: DataPacket, completionHandler: SendingCompletionHandler?)] = []
        for info in self.packetsSending {
            guard info.packetSent == nil && info.uploadTask?.isStarted != true else { continue }
            info.uploadTask?.close()
            if !silently {
                self.finalizeSending(packet: info.dataPacket, completionHandler: info.completionHandler, packetSent: false, payloadSent: false)
            }
            results.append((dataPacket: info.dataPacket, completionHandler: info.completionHandler))
            
            let taskString: String = info.uploadTask != nil ? "\(info.uploadTask!)" : "nil"
            if silently {
                Log.debug?.message("Reclaiming data packet <\(info.dataPacket.id)> with upload task <\(taskString)>. [\(self)]")
            }
            else {
                Log.debug?.message("Discarding data packet <\(info.dataPacket.id)> with upload task <\(taskString)>. [\(self)]")
            }
        }
        self.packetsSending = self.packetsSending.filter { $0.packetSent != nil || $0.uploadTask?.isStarted == true }
        return results
    }
    
    private class func createDispatchQueue(withLabel label: String) -> DispatchQueue {
        if #available(OSX 10.12, *) {
            return DispatchQueue(label: label, qos: DispatchQoS.background, autoreleaseFrequency: .workItem)
        }
        else {
            return DispatchQueue(label: label, qos: DispatchQoS.background)
        }
    }

}
