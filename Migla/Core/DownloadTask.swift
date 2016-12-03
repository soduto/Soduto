//
//  DownloadTask.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-12-03.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import CocoaAsyncSocket

public protocol DownloadTaskDelegate: class {
    func downloadTask(_ task: DownloadTask, finishedWithSuccess success: Bool)
}

public class DownloadTask: NSObject, GCDAsyncSocketDelegate {
    
    // MARK: Types
    
    private enum PayloadInfoProperty: String {
        case port = "port"
    }
    
    
    // MARK: Properties
    
    private static let bufferSize = 1024 * 64
    private static let downloadTimeout = 30.0
    
    public weak var delegate: DownloadTaskDelegate? = nil
    
    public var id: Int64
    public let connection: Connection
    private let port: UInt16
    private let payloadSize: Int64?
    private let writeQueue: DispatchQueue
    private let delegateQueue: DispatchQueue
    private var stream: OutputStream? = nil
    private var socket: GCDAsyncSocket? = nil
    private var bytesRead: Int64 = 0
    
    
    // MARK: Init / Deinit
    
    public init?(packet: DataPacket, connection: Connection, writeQueue: DispatchQueue = DispatchQueue.main, delegateQueue: DispatchQueue = DispatchQueue.main) {
        assert(packet.payloadInfo != nil, "Data packet expected to have payloadInfo")
        
        guard let port = packet.payloadInfo?[PayloadInfoProperty.port.rawValue] as? NSNumber else { return nil }
        
        self.id = packet.id
        self.connection = connection
        self.port = port.uint16Value
        self.payloadSize = packet.payloadSize
        self.writeQueue = writeQueue
        self.delegateQueue = delegateQueue
        
        super.init()
    }
    
    deinit {
        // Make sure we are clean
        self.socket?.disconnect()
        self.stream?.close()
    }
    
    
    // MARK: Public methods
    
    public func start(withStream stream: OutputStream) {
        self.stream = stream
        
        do {
            var address = self.connection.peerAddress
            address.port = self.port
            self.socket = GCDAsyncSocket(delegate: self, delegateQueue: self.writeQueue)
            try self.socket?.connect(toAddress: address.data)
        }
        catch {
            self.downloadFinished(success: false)
        }
    }
    
    public func cancel() {
        self.socket?.disconnect()
    }
    
    
    // MARK: GCDAsyncSocketDelegate
    
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        self.connection.secureClientSocket(sock)
    }
    
    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        self.writeData(data: data)
        self.tryReading(from: sock)
    }
    
    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        if sock === self.socket {
            let finished: Bool
            if let payloadSize = self.payloadSize {
                finished = self.bytesRead >= payloadSize
            }
            else if let error = err as? NSError {
                finished = error.domain == GCDAsyncSocketErrorDomain && error.code == GCDAsyncSocketError.closedError.rawValue
            }
            else {
                finished = false
            }
            
            if let error = err, !finished {
                Swift.print("Download socket disconnected with error: \(error)")
            }
            
            self.downloadFinished(success: finished)
        }
    }
    
    public func socketDidSecure(_ sock: GCDAsyncSocket) {
        self.beginReading(from: sock)
    }
    
    public func socket(_ sock: GCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void) {
        completionHandler(self.shoulTrustPeer(trust))
    }
    
    
    // MARK: Private methods
    
    private func beginReading(from sock: GCDAsyncSocket) {
        // Try schedule 2 batches at once to exploit concurrency - one batch could be writing while another is being prepared
        self.stream?.open()
        self.tryReading(from: sock)
        self.tryReading(from: sock)
    }
    
    private func tryReading(from sock: GCDAsyncSocket) {
        if self.bytesRead >= (self.payloadSize ?? Int64.max) || (self.payloadSize == nil && sock.isDisconnected) {
            sock.disconnect()
            return
        }
        
        if sock.isDisconnected || !sock.isSecure || !(self.stream?.hasSpaceAvailable ?? false) {
            sock.disconnect()
            return
        }
        
        sock.readData(withTimeout: DownloadTask.downloadTimeout, tag: Int(self.bytesRead))
    }
    
    private func writeData(data: Data) {
        guard let stream = self.stream else { return }
        
        var batchBytesWritten = 0 // bytes written from current data
        while stream.hasSpaceAvailable {
            let bytesToWrite: Int
            if let payloadSize = self.payloadSize {
                bytesToWrite = min(data.count - batchBytesWritten, Int(payloadSize - self.bytesRead))
            }
            else {
                bytesToWrite = data.count - batchBytesWritten
            }
            guard bytesToWrite > 0 else { break }
            
            let written = data.withUnsafeBytes { ptr in
                return stream.write(ptr.advanced(by: batchBytesWritten), maxLength: bytesToWrite)
            }
            guard written > 0 else { continue }
            
            batchBytesWritten += written
            self.bytesRead += Int64(written)
            
            guard batchBytesWritten < data.count else { break }
        }
    }
    
    private func downloadFinished(success: Bool) {
        self.socket?.disconnect()
        self.stream?.close()
        
        self.delegateQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.delegate?.downloadTask(strongSelf, finishedWithSuccess: success)
        }
    }
    
    private func shoulTrustPeer(_ trust: SecTrust) -> Bool {
        guard let peerCertificate = SecTrustGetCertificateAtIndex(trust, 0) else { return false }
        return self.connection.shouldTrustPeerCertificate(peerCertificate)
    }
}

