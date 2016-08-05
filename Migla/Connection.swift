//
//  Connection.swift
//  Migla
//
//  Created by Admin on 2016-08-04.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public protocol ConnectionDelegate {
    func connection(_ connection:Connection, switchedToState:Connection.State)
}

public class Connection: NSObject, StreamDelegate {
    
    public enum State {
        case Initializing
        case Open
        case Closed
    }
    
    public typealias Id = Connection
    
    
    
    public var delegate: ConnectionDelegate?
    
    public private(set) var state: State {
        didSet {
            self.delegate?.connection(self, switchedToState: self.state)
        }
    }
    
    public var id: Id {
        return self
    }
    
    private let address: SocketAddress
    private let inputStream: InputStream
    private let outputStream: NSOutputStream
    
    
    init?(address: SocketAddress, identityPacket packet: DataPacket) {
        guard packet.type == DataPacket.PacketType.Identity.rawValue else {
            return nil
        }
        
        self.address = address
        self.state = .Initializing
        
        var readStream:  Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        let hostData = address.data()
        let host = CFHostCreateWithAddress(kCFAllocatorDefault, hostData).takeRetainedValue()
        CFStreamCreatePairWithSocketToCFHost(kCFAllocatorDefault, host, Int32(address.port), &readStream, &writeStream)
        
        // Documentation suggests readStream and writeStream can be assumed to
        // be non-nil. If you believe otherwise, you can test if either is nil
        // and implement whatever error-handling you wish.
        
        self.inputStream = readStream!.takeRetainedValue()
        self.outputStream = writeStream!.takeRetainedValue()
        
        super.init()
        
        self.inputStream.delegate = self
        self.outputStream.delegate = self
        
//        self.inputStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
//        self.outputStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        
        self.inputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        self.outputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        
        self.inputStream.open()
        self.outputStream.open()
    }
    
    deinit {
        self.close()
    }
    
    
    public func stream(_ stream: Stream, handle: Stream.Event) {
        switch handle {
        case Stream.Event.openCompleted:
            self.state = .Open
        case Stream.Event.endEncountered, Stream.Event.errorOccurred:
            self.close()
        default:
            break
        }
    }
    
    
    private func close() {
        self.inputStream.close()
        self.outputStream.close()
        self.state = .Closed
    }
}
