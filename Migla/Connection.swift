//
//  Connection.swift
//  Migla
//
//  Created by Admin on 2016-08-04.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public enum ConnectionError: Error {
    case StreamWriteFailed
}

public protocol ConnectionDelegate {
    func connection(_ connection:Connection, didSwitchToState:Connection.State)
    func connection(_ connection:Connection, didSendPacket:DataPacket)
}

private struct SendContext {
    
    let packet: DataPacket
    let serializedPacket: [UInt8]
    var bytesSent: Int = 0
    var isFinished: Bool {
        return serializedPacket.count <= bytesSent
    }
    
    init?(packet: DataPacket) {
        guard let data = try? packet.serialize() else {
            return nil
        }
        self.packet = packet
        self.serializedPacket = data
    }
    
}

public class Connection: NSObject, StreamDelegate {
    
    public enum State {
        case Initializing
        case Open
        case Closed
    }
    
    
    
    public var delegate: ConnectionDelegate?
    
    public private(set) var state: State {
        didSet {
            self.delegate?.connection(self, didSwitchToState: self.state)
        }
    }
    
    public let protocolVersion: Int
    public let address: SocketAddress
    
    private let cfStream: CFReadStream
    private let inputStream: InputStream
    private let outputStream: NSOutputStream
    private let sslCertificates: [AnyObject]
    private var packetsToSend: [DataPacket] = []
    private var sendContext: SendContext?
    
    
    
    init?(address: SocketAddress, identityPacket packet: DataPacket) {
        guard packet.type == DataPacket.PacketType.Identity.rawValue else { return nil }
        guard let protocolVersion = packet.body[DataPacket.BodyProperty.ProtocolVerion.rawValue] as? NSNumber else { return nil }
        guard let sslCertificates = Connection.getSSLCertificates() else { return nil }
        
        // Enable diagnostics for debugging
        setenv("CFNETWORK_DIAGNOSTICS","3",1);
        
        let sock = Connection.createSocket(address: address)
        var readStream:  Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, sock, &readStream, &writeStream)
        guard readStream != nil && writeStream != nil else {
            return nil
        }
        
        self.cfStream = readStream!.takeRetainedValue()
        self.inputStream = readStream!.takeRetainedValue()
        self.outputStream = writeStream!.takeRetainedValue()
        self.sslCertificates = sslCertificates
        self.address = address
        self.protocolVersion = protocolVersion.intValue
        self.state = .Initializing
        
        super.init()
        
        self.inputStream.delegate = self
        self.outputStream.delegate = self
        
        self.inputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        self.outputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        
        self.inputStream.open()
        self.outputStream.open()
    }
    
    deinit {
        self.close()
    }
    
    
    
    public func send(_ packet:DataPacket) {
        self.packetsToSend.append(packet)
        sendPendingData()
    }
    
    public func switchOnSSL() {
//        self.inputStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
//        self.outputStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        
        let sslSettings: [String: AnyObject] = [
            kCFStreamSSLIsServer as String: true,
            kCFStreamSSLCertificates as String: self.sslCertificates
        ]
//        CFReadStreamSetProperty(self.cfStream, CFStreamPropertyKey.init(kCFStreamPropertySSLSettings), sslSettings)
        
//        self.outputStream.setProperty(self.sslCertificates, forKey: Stream.PropertyKey.init(rawValue: kCFStreamSSLCertificates as String))
//        self.outputStream.setProperty(true, forKey: Stream.PropertyKey.init(rawValue: kCFStreamSSLIsServer as String))
//        self.outputStream.setProperty(sslSettings, forKey: Stream.PropertyKey.init(rawValue: kCFStreamPropertySSLSettings as String))
        
        self.outputStream.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: .socketSecurityLevelKey)
        
        self.outputStream.setProperty(self.sslCertificates, forKey: Stream.PropertyKey.init(rawValue: kCFStreamSSLCertificates as String))
        self.outputStream.setProperty(true, forKey: Stream.PropertyKey.init(rawValue: kCFStreamSSLIsServer as String))
        self.outputStream.setProperty(sslSettings, forKey: Stream.PropertyKey.init(rawValue: kCFStreamPropertySSLSettings as String))
        
        
//        let sslContext = SSLCreateContext(kCFAllocatorDefault, SSLProtocolSide.serverSide, SSLConnectionType.streamType)
//        self.outputStream.setProperty(sslContext, forKey: Stream.PropertyKey.init(rawValue: kCFStreamPropertySSLContext as String))
//        
////        self.outputStream.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: .socketSecurityLevelKey)
        
//        if let sslContext = self.inputStream.property(forKey: Stream.PropertyKey.init(rawValue: kCFStreamPropertySSLContext as String)) {
//            SSLGet
//            Swift.print("sslContext: \(sslContext)");
//        }
    }
    
    
    
    public func stream(_ stream: Stream, handle event: Stream.Event) {
        switch event {
        case Stream.Event.openCompleted:
            Swift.print("Stream open completed: \(stream), \(stream.streamError)")
            if self.inputStream.streamStatus == .open && self.outputStream.streamStatus == .open && self.state == .Initializing {
                self.state = .Open
            }
        case Stream.Event.errorOccurred:
            Swift.print("Stream error encountered: \(stream), \(stream.streamError)")
            self.close()
        case Stream.Event.endEncountered:
            Swift.print("Stream end encountered: \(stream), \(stream.streamError)")
            self.close()
        case Stream.Event.hasBytesAvailable:
            Swift.print("Stream has bytes available: \(stream)")
            var bufferOpt: UnsafeMutablePointer<UInt8>? = nil
            var length: Int = 0
            if self.inputStream.getBuffer(&bufferOpt, length: &length),
                let buffer = bufferOpt {
                
                let bufferPtr = UnsafeBufferPointer(start: buffer, count: length)
                let data = Data(bufferPtr)
                Swift.print("Received data: \(data)");
            }
        case Stream.Event.hasSpaceAvailable:
            Swift.print("Stream has space available: \(stream)")
            sendPendingData()
        default:
            Swift.print("Stream unhandled event: \(stream) \(event)")
        }
    }
    
    
    
    private func close() {
        self.inputStream.close()
        self.outputStream.close()
        self.state = .Closed
    }
    
    private func sendPendingData() {
        assert(self.state != .Closed, "Cannot send data on closed connection")
        
        while self.outputStream.hasSpaceAvailable {
            if let sendContext = self.sendContext, !sendContext.isFinished {
                // send data using current send context
                let remainingData = sendContext.serializedPacket.suffix(from: sendContext.bytesSent)
                remainingData.withUnsafeBufferPointer({ bufferPointer in
                    if let pointer = bufferPointer.baseAddress {
                        let written = self.outputStream.write(pointer, maxLength: bufferPointer.count)
                        if written > 0 {
                            // update send context with sent bytes count
                            self.sendContext!.bytesSent += written
                            if self.sendContext!.isFinished {
                                self.delegate?.connection(self, didSendPacket: sendContext.packet)
                                self.sendContext = nil
                            }
                        }
                    }
                })
            }
            else if self.packetsToSend.count > 0 {
                // setup new send context from pending packet
                let packet = self.packetsToSend.removeFirst()
                self.sendContext = SendContext(packet: packet)
            }
            else {
                // nothing to send
                break
            }
        }
    }


    private static func createSocket(address: SocketAddress) -> CFSocketNativeHandle {
        let sock = socket(Int32(address.family), SOCK_STREAM, IPPROTO_TCP)
        
        // connect
        var mutableAddress = address
        connect(sock, mutableAddress.pointer(), mutableAddress.size)
        
        // set options
        var value: Int = 0
        let valueSize = socklen_t(sizeofValue(value))
        
        // enable keepalive
        value = 1
        setsockopt(sock, SOL_SOCKET, TCP_KEEPALIVE, &value, valueSize)
        
        // set interval between keepalive packets (seconds)
        value = 5
        setsockopt(sock, IPPROTO_TCP, TCP_KEEPINTVL, &value, valueSize)
        
        // set number of missed keepalive packets before disconnecting
        value = 3
        setsockopt(sock, IPPROTO_TCP, TCP_KEEPINTVL, &value, valueSize)
        
        return sock
    }
    
    private static func getSSLCertificates() -> [AnyObject]? {
        var error: NSError? = nil
        if let identity = MYGetOrCreateAnonymousIdentity("Migla", 60.0 * 60.0 * 24.0 * 365.0 * 10.0, &error)?.takeRetainedValue() {
            //        var certificate: SecCertificate? = nil
            //        SecIdentityCopyCertificate(identity, &certificate)
            //
            //        var commonName:CFString? = nil
            //        SecCertificateCopyCommonName(certificate!, &commonName)
            //        Swift.print("commonName: \(commonName)")
            //
            //        var error:Unmanaged<CFError>? = nil
            //        let values = (SecCertificateCopyValues(certificate!, nil, &error) as Dictionary?)
            //
            //        for (key, value) in values! {
            //            Swift.print("Key: \(key)")
            //            Swift.print("Value: \(value)")
            //        }
            return [identity]
        }
        else {
            Swift.print("Failed to get certificates for SSL: \(error)")
            return nil
        }
    }
}
