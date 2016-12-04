//
//  SocketAddress.swift
//  Migla
//
//  Created by Admin on 2016-08-03.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public struct SocketAddress: CustomStringConvertible {
    
    var storage = sockaddr_storage()
    
    public var size: socklen_t {
        return socklen_t(self.storage.ss_len)
    }
    
    public var family: sa_family_t {
        return sa_family_t(self.storage.ss_family)
    }
    
    public var port: in_port_t {
        get {
            var mutableSelf = self
            switch Int32(self.family) {
            case AF_INET:
                let ptr: UnsafeMutablePointer<sockaddr_in> = mutableSelf.pointer()
                return CFSwapInt16BigToHost(ptr.pointee.sin_port)
            case AF_INET6:
                let ptr: UnsafeMutablePointer<sockaddr_in6> = mutableSelf.pointer()
                return CFSwapInt16BigToHost(ptr.pointee.sin6_port)
            default:
                assert(false, "Cant retrieve port for this type address")
                return 0
            }
        }
        set {
            switch Int32(self.family) {
            case AF_INET:
                let ptr: UnsafeMutablePointer<sockaddr_in> = self.pointer()
                ptr.pointee.sin_port = CFSwapInt16HostToBig(newValue)
            case AF_INET6:
                let ptr: UnsafeMutablePointer<sockaddr_in6> = self.pointer()
                ptr.pointee.sin6_port = CFSwapInt16HostToBig(newValue)
            default:
                assert(false, "Cant set port for this type address")
            }
        }
    }
    
    public var description: String {
        if (Int32(self.storage.ss_family) == AF_INET) {
            var mutableStorage = self.storage
            let ptr: UnsafePointer<sockaddr_in> = cast(pointer: &mutableStorage)
            let address = String(cString: inet_ntoa(ptr.pointee.sin_addr))
            return "\(address):\(self.port)"
        }
        if (Int32(self.storage.ss_family) == AF_INET6) {
            var mutableStorage = self.storage
            let ptr: UnsafePointer<sockaddr_in6> = cast(pointer: &mutableStorage)
            
            var sin6Addr = ptr.pointee.sin6_addr
            var cString = [Int8](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            inet_ntop(AF_INET6, &sin6Addr, &cString, socklen_t(cString.count));
            let address = String(cString: cString)
            
            return "[\(address)]:\(self.port)"
            
        }
        return "\(self.storage)"
    }
    
    public var data: Data {
        var mutableAddress = self
        let ptr: UnsafeMutablePointer<UInt8> = mutableAddress.pointer()
        return Data(bytes: ptr, count: Int(self.size))
    }
    
    
    
    init() {}
    
    init<T>(addr: T) {
        assert(MemoryLayout<sockaddr_storage>.size >= MemoryLayout<T>.size, "Address does not fit into sockaddr_storage")
        
        let dest: UnsafeMutablePointer<T> = cast(pointer: &self.storage)
        dest.pointee = addr
    }
    
    init(addr: UnsafeRawPointer, size: socklen_t) {
        assert(MemoryLayout<sockaddr_storage>.size >= Int(size), "Address does not fit into sockaddr_storage")
        
        let dest: UnsafeMutablePointer<UInt8> = cast(pointer: &self.storage)
        memcpy(dest, addr, Int(size))
    }
    
    init(data: Data) {
        assert(MemoryLayout<sockaddr_storage>.size >= data.count, "Data does not fit into sockaddr_storage")
        
        let dest: UnsafeMutablePointer<UInt8> = cast(pointer: &self.storage)
        data.copyBytes(to: dest, count: data.count)
    }
    
    init(bytes: [UInt8]) {
        assert(MemoryLayout<sockaddr_storage>.size >= bytes.count, "Bytes do not fit into sockaddr_storage")
        
        let dest: UnsafeMutablePointer<UInt8> = cast(pointer: &self.storage)
        _ = bytes.withUnsafeBufferPointer { buffer in
            memcpy(dest, buffer.baseAddress, bytes.count)
        }
    }
    
    init?(ipv4: String) {
        var addr: in_addr_t = 0
        guard let buffer: [Int8] = ipv4.cString(using: .ascii) else { return nil }
        guard inet_pton(AF_INET, buffer, &addr) != 0 else { return nil }
        
        let ptr: UnsafeMutablePointer<sockaddr_in> = self.pointer()
        ptr.pointee.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        ptr.pointee.sin_family = sa_family_t(AF_INET)
        ptr.pointee.sin_addr = in_addr(s_addr: addr)
    }
    
    
    
    mutating func pointer<T>() -> UnsafeMutablePointer<T> {
        return cast(pointer: &self.storage)
    }
}
