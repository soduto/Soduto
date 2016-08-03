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
    
    var size: socklen_t {
        return socklen_t(self.storage.ss_len)
    }
    
    public var description: String {
        if (Int32(self.storage.ss_family) == AF_INET) {
            // Print nice info about IPv4 address
            var mutableStorage = self.storage
            let ptr: UnsafePointer<sockaddr_in> = cast(pointer: &mutableStorage)
            let byte1 = (ptr.pointee.sin_addr.s_addr & 0xff000000) >> 24
            let byte2 = (ptr.pointee.sin_addr.s_addr & 0x00ff0000) >> 16
            let byte3 = (ptr.pointee.sin_addr.s_addr & 0x0000ff00) >> 8
            let byte4 = (ptr.pointee.sin_addr.s_addr & 0x000000ff)
            return "IPv4: \(byte1).\(byte2).\(byte3).\(byte4), port:\(ptr.pointee.sin_port)"
        }
        if (Int32(self.storage.ss_family) == AF_INET6) {
            // Print nice info about IPv6 address
            var mutableStorage = self.storage
            let ptr: UnsafePointer<sockaddr_in6> = cast(pointer: &mutableStorage)
            let (b1, b2, b3, b4, b5, b6, b7, b8) = ptr.pointee.sin6_addr.__u6_addr.__u6_addr16
            return String(format: "IPv6: %04X:%04X:%04X:%04X:%04X:%04X:%04X:%04X, port:%d", b1, b2, b3, b4, b5, b5, b6, b7, b8, ptr.pointee.sin6_port)
        }
        return "\(self.storage)"
    }
    
    
    
    init() {}
    
    init<T>(addr: T) {
        assert(sizeofValue(self.storage) >= sizeofValue(addr), "Address does not fit into sockaddr_storage")
        
        let dest: UnsafeMutablePointer<T> = cast(pointer: &self.storage)
        dest.pointee = addr
    }
    
    init(addr: UnsafePointer<Void>!, size: socklen_t) {
        assert(sizeofValue(self.storage) >= Int(size), "Address does not fit into sockaddr_storage")
        
        let dest: UnsafeMutablePointer<UInt8> = cast(pointer: &self.storage)
        memcpy(dest, addr, Int(size))
    }
    
    init(data: Data) {
        assert(sizeofValue(self.storage) >= data.count, "Data does not fit into sockaddr_storage")
        
        let dest: UnsafeMutablePointer<UInt8> = cast(pointer: &self.storage)
        data.copyBytes(to: dest, count: data.count)
    }
    
    init(bytes: [UInt8]) {
        assert(sizeofValue(self.storage) >= bytes.count, "Bytes do not fit into sockaddr_storage")
        
        let dest: UnsafeMutablePointer<UInt8> = cast(pointer: &self.storage)
        _ = bytes.withUnsafeBufferPointer { buffer in
            memcpy(dest, buffer.baseAddress, bytes.count)
        }
    }
    
    
    
    mutating func pointer<T>() -> UnsafeMutablePointer<T> {
        assert(sizeofValue(self.storage) >= sizeof(T.self), "Pointer type does not fit into sockaddr_storage")
        
        return cast(pointer: &self.storage)
    }
    
    mutating func pointer<T>() -> UnsafePointer<T> {
        assert(sizeofValue(self.storage) >= sizeof(T.self), "Pointer type does not fit into sockaddr_storage")
        
        return cast(pointer: &self.storage)
    }
}
