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
    private static let maxBufferSize = 1024 * 4
    private static let listenTimeout = 30.0
    private static let uploadTimeout = 30.0
    
    private let connection: Connection
    private let payload: InputStream
    private let payloadSize: Int
    private let delegateQueue: DispatchQueue
    private let listenTimeoutTimer: Timer
    private let listeningSocket: GCDAsyncSocket
    private var uploadingSocket: GCDAsyncSocket? = nil
    private var bytesSent = 0
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
            Swift.print("Serving payload for packet \(packet) on port \(listeningSocket.localPort) has timedout")
            listeningSocket.disconnect()
        })
        
        super.init()
        
        self.listeningSocket.delegate = self
        for port: UInt16 in UploadTask.startPort...UploadTask.endPort {
            do {
                try self.listeningSocket.accept(onPort: port)
                Swift.print("Providing payload on port \(port)")
            }
            catch {}
        }
        guard self.listeningSocket.isConnected else { return nil }
        
        RunLoop.current.add(self.listenTimeoutTimer, forMode: .commonModes)
    }
    
    deinit {
        // Make sure we are clean
        self.listeningSocket.disconnect()
        self.uploadingSocket?.disconnect()
    }
    
    
    // MARK: GCDAsyncSocketDelegate
    
    public func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        self.connection.secureServerSocket(sock)
        self.uploadingSocket = sock
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
            if self.payloadSize == DataPacket.payloadSizeUndefined {
                bytesToRead = UploadTask.maxBufferSize
            }
            else {
                bytesToRead = min(self.payloadSize - self.bytesSent, UploadTask.maxBufferSize)
            }
            
            guard bytesToRead > 0 else { break }
            
            let read = self.payload.read(&self.readBuffer, maxLength: bytesToRead)
            let data = Data(self.readBuffer.prefix(upTo: read))
            self.uploadingSocket?.write(data, withTimeout: UploadTask.uploadTimeout, tag: self.bytesSent + read)
            
            batchBytesSent += read
            self.bytesSent += read
            
            guard batchBytesSent >= UploadTask.maxBufferSize else { break }
        }
        
        if self.bytesSent >= self.payloadSize || !self.payload.hasBytesAvailable {
            self.uploadingSocket?.disconnectAfterWriting()
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
