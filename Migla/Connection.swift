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
    case StreamWriteFailed
}

public protocol ConnectionDelegate {
    func connection(_ connection:Connection, didSwitchToState:Connection.State)
    func connection(_ connection:Connection, didSendPacket:DataPacket)
    func connection(_ connection:Connection, didReadPacket:DataPacket)
}

public class Connection: NSObject, GCDAsyncSocketDelegate {
    
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
    
    private let socket: GCDAsyncSocket
    private let sslCertificates: [AnyObject]
    private var packetsToSend: [DataPacket] = []
    
    // In readBuffers we accumulate data received from socket until whole packet data is received
    private var readBuffers: [AnySequence<UInt8>] = []
    
    
    init?(address: SocketAddress, identityPacket packet: DataPacket) {
        guard packet.type == DataPacket.PacketType.Identity.rawValue else { return nil }
        guard let protocolVersion = packet.body[DataPacket.BodyProperty.ProtocolVerion.rawValue] as? NSNumber else { return nil }
        guard let sslCertificates = Connection.getSSLCertificates() else { return nil }
        
        self.socket = GCDAsyncSocket(delegate: nil, delegateQueue: DispatchQueue.main)
        self.sslCertificates = sslCertificates
        self.address = address
        self.protocolVersion = protocolVersion.intValue
        self.state = .Initializing

        super.init()
        
        self.socket.delegate = self
        do {
            try self.socket.connect(toAddress: address.data())
        }
        catch {
            Swift.print("Could not connect to address \(address): \(error)")
            return nil
        }
    }
    
    deinit {
        self.close()
    }
    
    
    
    public func send(_ packet:DataPacket) {
        self.packetsToSend.append(packet)
        if let bytes = try? packet.serialize() {
            let data = Data(bytes: bytes)
            self.socket.write(data, withTimeout: -1, tag: Int(packet.id))
        }
    }
    
    public func continueWithSSL() {
        // Enable SSL and start listening for input packets
        let settings: [String:NSObject] = [
            kCFStreamSSLCertificates as String: self.sslCertificates as NSArray,
            kCFStreamSSLIsServer as String: NSNumber(value: true)
        ]
        
        self.socket.startTLS(settings)
        self.socket.readData(withTimeout: -1, tag: 0)
    }
    
    public func continueWithoutSSL() {
        // SSL wont be needed - start listening for input packets
        self.socket.readData(withTimeout: -1, tag: 0)
    }
    
    
    
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        Swift.print("socket:didConnectToHost:port: \(sock) \(host) \(port)")
        self.state = .Open
    }
    
    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        Swift.print("socket:didWriteDataWithTag: \(sock) \(tag)")
        
        let indexOpt = self.packetsToSend.index { packet -> Bool in
            return Int(packet.id) == tag
        }
        if let index = indexOpt {
            let packet = self.packetsToSend.remove(at: index)
            self.delegate?.connection(self, didSendPacket: packet)
        }
    }
    
    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        Swift.print("socket:didRead:withTag: \(sock) \(data) \(tag)")
        
        var splits: [AnySequence<UInt8>] = data.split(separator: UInt8(ascii: "\n"), maxSplits: Int.max, omittingEmptySubsequences: false)
        for i in 0..<splits.count {
            let split = splits[i]
            self.readBuffers.append(split)

            // The last split will contain incomplete packet data or be empty if packets where read completely
            // The other splits will have data for complete packets and can be deserialized
            if i < splits.count - 1 {
                self.readPacket()
            }
        }
    }
    
    public func socketDidSecure(_ sock: GCDAsyncSocket) {
        Swift.print("socketDidSecure: \(sock)")
    }
    
    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        Swift.print("socketDidDisconnect:withError: \(sock) \(err)")
        self.close()
    }
    
    
    
    
    private func close() {
        self.socket.disconnect()
        self.state = .Closed
    }
    
    private func readPacket() {
        let joinedBuffers = self.readBuffers.joined(separator: [UInt8]())
        var bytes = [UInt8](joinedBuffers)
        self.readBuffers = []
        
        if bytes.count == 0 {
            return
        }
        
        if let packet = DataPacket(json: &bytes) {
            self.delegate?.connection(self, didReadPacket: packet)
        }
        else {
            Swift.print("Could not deserialize DataPacket")
        }
    }

    
    
    private static func getSSLCertificates() -> [AnyObject]? {
        var error: NSError? = nil
        if let identity = MYGetOrCreateAnonymousIdentity("Migla", 60.0 * 60.0 * 24.0 * 365.0 * 10.0, &error)?.takeUnretainedValue() {
            
            var certificateOpt: SecCertificate? = nil
            SecIdentityCopyCertificate(identity, &certificateOpt)
        
            if let certificate = certificateOpt {
                
//                var commonName:CFString? = nil
//                SecCertificateCopyCommonName(certificate, &commonName)
//                Swift.print("Using certificate with commonName: \(commonName)")
                
//                var error:Unmanaged<CFError>? = nil
//                let values = (SecCertificateCopyValues(certificate!, nil, &error) as Dictionary?)
//        
//                for (key, value) in values! {
//                    Swift.print("Key: \(key)")
//                    Swift.print("Value: \(value)")
//                }
                
                return [identity, certificate]
            }
            else {
                Swift.print("Failed to extract certificate from identity")
                return nil
            }
        }
        else {
            Swift.print("Failed to get certificates for SSL: \(error)")
            return nil
        }
    }
}
