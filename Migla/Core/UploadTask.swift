//
//  UploadOperation.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-11-28.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import CocoaAsyncSocket

public protocol UploadTaskDelegate: class {
    func uploadTask(_ task: UploadTask, finishedWithSuccess success: Bool)
}

public class UploadTask: NSObject, GCDAsyncSocketDelegate {
    
    // MARK: Types
    
    private enum PayloadInfoProperty: String {
        case port = "port"
    }
    

    // MARK: Properties
    
    public weak var delegate: UploadTaskDelegate? = nil
    
    public var payloadInfo: DataPacket.PayloadInfo {
        return [ PayloadInfoProperty.port.rawValue: self.listeningSocket.localPort as AnyObject ]
    }
    
    private static let startPort: UInt16 = 1739
    private static let endPort: UInt16 = 1764
    private static let maxBufferSize = 1024 * 64
    private static let listenTimeout = 30.0
    private static let uploadTimeout = 30.0
    
    private let connection: Connection
    private let payload: InputStream
    private let payloadSize: Int64?
    private let delegateQueue: DispatchQueue
    private let listenTimeoutTimer: Timer
    private let listeningSocket: GCDAsyncSocket
    private var uploadingSocket: GCDAsyncSocket? = nil
    private var bytesSent: Int64 = 0
    private var lastBytesDone: UInt = 0
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
        self.listenTimeoutTimer = Timer(timeInterval: UploadTask.listenTimeout, repeats: false, block: { _ in
            guard listeningSocket.isConnected else { return }
            Swift.print("Serving payload for packet \(packet) on port \(listeningSocket.localPort) has timedout")
            listeningSocket.disconnect()
        })
        
        super.init()
        
        self.listeningSocket.delegate = self
        var listening = false
        for port: UInt16 in UploadTask.startPort...UploadTask.endPort {
            do {
                try self.listeningSocket.accept(onPort: port)
                listening = true
                Swift.print("Providing payload on port \(port)")
                break
            }
            catch {}
        }
        guard listening else { return nil }
        
        RunLoop.current.add(self.listenTimeoutTimer, forMode: .commonModes)
    }
    
    deinit {
        // Make sure we are clean
        self.listeningSocket.disconnect()
        self.uploadingSocket?.disconnect()
        self.payload.close()
    }
    
    
    // MARK: GCDAsyncSocketDelegate
    
    public func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        guard self.uploadingSocket == nil else { return }
        
        self.connection.secureServerSocket(newSocket)
        self.uploadingSocket = newSocket
        self.listeningSocket.disconnect()
    }
    
    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        self.trySend(to: sock)
    }
    
    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        if sock === self.listeningSocket {
            if let error = err {
                Swift.print("Upload listening socket disconnected with error: \(error)")
            }
            if self.uploadingSocket == nil {
                self.uploadFinished(success: false)
            }
        }
        else if sock === self.uploadingSocket {
            if let error = err {
                Swift.print("Upload listening socket disconnected with error: \(error)")
            }
            self.uploadFinished(success: err == nil)
        }
    }
    
    public func socketDidSecure(_ sock: GCDAsyncSocket) {
        // Try schedule 2 batches at once to exploit concurrency - one batch could be sent while another is being prepared
        self.trySend(to: sock)
        self.trySend(to: sock)
    }
    
    public func socket(_ sock: GCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void) {
        completionHandler(self.shoulTrustPeer(trust))
    }
    
    
    // MARK: Private methods
    
    private func trySend(to: GCDAsyncSocket) {
        
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
            self.uploadingSocket?.write(data, withTimeout: UploadTask.uploadTimeout, tag: Int(self.bytesSent + Int64(read)))
            
            batchBytesSent += read
            self.bytesSent += Int64(read)
            
            guard batchBytesSent < UploadTask.maxBufferSize else { break }
        }
        
        if (self.payloadSize != nil && self.bytesSent >= self.payloadSize!) || !self.payload.hasBytesAvailable {
            self.uploadingSocket?.disconnectAfterWriting()
            self.payload.close()
        }
    }
    
    private func uploadFinished(success: Bool) {
        self.delegate?.uploadTask(self, finishedWithSuccess: success)
    }
    
    private func shoulTrustPeer(_ trust: SecTrust) -> Bool {
        guard let peerCertificate = SecTrustGetCertificateAtIndex(trust, 0) else { return false }
        return self.connection.shouldTrustPeerCertificate(peerCertificate)
    }
}
