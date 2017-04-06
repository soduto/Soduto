//
//  UploadOperation.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-11-28.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import CocoaAsyncSocket
import CleanroomLogger

public protocol UploadTaskDelegate: class {
    func uploadTask(_ task: UploadTask, finishedWithSuccess success: Bool)
}

public class UploadTask: NSObject, GCDAsyncSocketDelegate {
    
    // MARK: Types
    
    private enum PayloadInfoProperty: String {
        case port = "port"
    }
    

    // MARK: Properties
    
    public static let portReleaseNotification: Notification.Name = Notification.Name(rawValue: "com.soduto.uploadTask.portReleasedNotification")
    
    public weak var delegate: UploadTaskDelegate? = nil
    
    public var payloadInfo: DataPacket.PayloadInfo {
        return [ PayloadInfoProperty.port.rawValue: self.listeningSocket.localPort as AnyObject ]
    }
    
    public var isStarted: Bool { return self.uploadingSocket != nil }
    
    private static let startPort: UInt16 = 1739
    private static let endPort: UInt16 = 1764
    private static let maxBufferSize = 1024 * 64
    private static let listenTimeout = 30.0
    private static let uploadTimeout = 30.0
    private static var portsManagementLock = NSLock()
    private static var usedPorts: [UInt16] = []
    
    private let connection: Connection
    private let payload: InputStream
    private let payloadSize: Int64?
    private let delegateQueue: DispatchQueue
    private let listenTimeoutTimer: Timer
    private let listeningSocket: GCDAsyncSocket
    private var uploadingSocket: GCDAsyncSocket? = nil
    private var listeningPort: UInt16 = 0
    private var bytesSent: Int64 = 0
    private var readBuffer = [UInt8](repeating: 0, count: UploadTask.maxBufferSize)
    
    
    // MARK: Init / Deinit
    
    public init?(packet: DataPacket, connection: Connection, readQueue: DispatchQueue = DispatchQueue.main, delegateQueue: DispatchQueue = DispatchQueue.main) {
        assert(packet.hasPayload(), "Data packet expected to have payload")
        
        guard packet.hasPayload() else { return nil }
        guard let payload = packet.payload else { return nil }
        
        self.connection = connection
        self.payload = payload
        self.payloadSize = packet.payloadSize
        self.delegateQueue = delegateQueue
        self.listeningSocket = GCDAsyncSocket(delegate: nil, delegateQueue: readQueue)
        let listeningSocket = self.listeningSocket
        self.listenTimeoutTimer = Timer.compatTimer(withTimeInterval: UploadTask.listenTimeout, repeats: false, block: { _ in
            // Dont check for listeningSocket.isConnected, because it is false for listening socket
            guard !listeningSocket.isDisconnected else { return }
            Log.info?.message("Serving payload for packet of type '\(packet.type)' on port \(listeningSocket.localPort) has timedout")
            listeningSocket.disconnect()
        })
        
        super.init()
        
        self.listeningSocket.delegate = self
        for port: UInt16 in UploadTask.startPort...UploadTask.endPort {
            guard !type(of: self).isPortUsed(port) else { continue }
            do {
                try self.listeningSocket.accept(onPort: port)
                self.listeningPort = port
                type(of: self).usePort(port)
                Log.debug?.message("Providing payload for packet with id <\(packet.id)> on port \(port). [\(self)]")
                break
            }
            catch {}
        }
        guard listeningPort > 0 else {
            return nil
        }
        
        RunLoop.current.add(self.listenTimeoutTimer, forMode: .commonModes)
    }
    
    deinit {
        // Make sure we are clean
        self.close()
    }
    
    
    // MARK: Public methods
    
    public func close() {
        Log.debug?.message("close() [\(self)]")
        
        self.delegate = nil
        self.listeningSocket.disconnect()
        self.uploadingSocket?.disconnect()
        self.payload.close()
    }
    
    
    // MARK: Ports managements
    
    public static func hasUsedPorts() -> Bool {
        self.portsManagementLock.lock()
        defer { self.portsManagementLock.unlock() }
        
        return self.usedPorts.count > 0
    }
    
    public static func isPortUsed(_ port: UInt16) -> Bool {
        self.portsManagementLock.lock()
        defer { self.portsManagementLock.unlock() }
        
        return self.usedPorts.index(of: port) != nil
    }
    
    public static func usePort(_ port: UInt16) {
        self.portsManagementLock.lock()
        defer { self.portsManagementLock.unlock() }
        
        assert(self.usedPorts.index(of: port) == nil)
        self.usedPorts.append(port)
    }
    
    public static func releasePort(_ port: UInt16) {
        self.portsManagementLock.lock()
        defer { self.portsManagementLock.unlock() }
        
        if let index = self.usedPorts.index(of: port) {
            self.usedPorts.remove(at: index)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: portReleaseNotification, object: port as AnyObject)
            }
        }
        else {
            assertionFailure("Could not release port (\(port)) which was not being used.")
        }
    }
    
    
    // MARK: GCDAsyncSocketDelegate
    
    public func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        guard self.uploadingSocket == nil else { return }
        
        self.connection.secureServerSocket(newSocket)
        self.uploadingSocket = newSocket
        self.listeningSocket.disconnect()
    }
    
    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        self.trySending(to: sock)
    }
    
    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        Log.debug?.message("socketDidDisconnect(<\(sock)>, withError: <\(err)>) [\(self)]")
        
        if sock === self.listeningSocket {
            if let error = err {
                Log.error?.message("Upload listening socket disconnected with error: \(error)")
            }
            self.listenTimeoutTimer.invalidate()
            if self.uploadingSocket == nil {
                self.uploadFinished(success: false)
            }
        }
        else if sock === self.uploadingSocket {
            if let error = err {
                Log.error?.message("Upload listening socket disconnected with error: \(error)")
            }
            self.uploadFinished(success: err == nil)
        }
    }
    
    public func socketDidSecure(_ sock: GCDAsyncSocket) {
        self.beginSending(to: sock)
    }
    
    public func socket(_ sock: GCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void) {
        completionHandler(self.shoulTrustPeer(trust))
    }
    
    
    // MARK: Private methods
    
    private func beginSending(to sock: GCDAsyncSocket) {
        // Try schedule 2 batches at once to exploit concurrency - one batch could be sent while another is being prepared
        self.payload.open()
        self.trySending(to: sock)
        self.trySending(to: sock)
    }
    
    private func trySending(to sock: GCDAsyncSocket) {
        
        var batchBytesSent = 0 // bytes sent per this trySend call
        while self.payload.hasBytesAvailable {
            let bytesToRead: Int
            if let payloadSize = self.payloadSize {
                bytesToRead = min(Int(payloadSize - self.bytesSent), UploadTask.maxBufferSize)
            }
            else {
                bytesToRead = UploadTask.maxBufferSize
            }
            
            guard bytesToRead > 0 else { break }
            
            let read = self.payload.read(&self.readBuffer, maxLength: bytesToRead)
            guard read > 0 else { continue }
            
            let data = Data(bytes: &self.readBuffer, count: read)
            sock.write(data, withTimeout: UploadTask.uploadTimeout, tag: Int(self.bytesSent + Int64(read)))
            
            batchBytesSent += read
            self.bytesSent += Int64(read)
            
            guard batchBytesSent < UploadTask.maxBufferSize else { break }
        }
        
        if (self.payloadSize != nil && self.bytesSent >= self.payloadSize!) || !self.payload.hasBytesAvailable {
            sock.disconnectAfterWriting()
            self.payload.close()
        }
    }
    
    private func uploadFinished(success: Bool) {
        Log.debug?.message("uploadFinished(<\(success)>) [\(self)]")
        
        type(of: self).releasePort(self.listeningPort)
        self.delegateQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.delegate?.uploadTask(strongSelf, finishedWithSuccess: success)
        }
    }
    
    private func shoulTrustPeer(_ trust: SecTrust) -> Bool {
        guard let peerCertificate = SecTrustGetCertificateAtIndex(trust, 0) else { return false }
        return self.connection.shouldTrustPeerCertificate(peerCertificate)
    }
}
