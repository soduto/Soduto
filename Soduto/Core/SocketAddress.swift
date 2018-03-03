//
//  SocketAddress.swift
//  Soduto
//
//  Created by Admin on 2016-08-03.
//  Copyright © 2016 Soduto. All rights reserved.
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
    
    public var isIPv4: Bool { return Int32(self.family) == AF_INET }
    public var isIPv6: Bool { return Int32(self.family) == AF_INET6 }
    
    public var port: in_port_t {
        get {
            var mutableSelf = self
            switch Int32(self.family) {
            case AF_INET:
                return mutableSelf.withPointer { (ptr: UnsafeMutablePointer<sockaddr_in>) in
                    return CFSwapInt16BigToHost(ptr.pointee.sin_port)
                }
            case AF_INET6:
                return mutableSelf.withPointer { (ptr: UnsafeMutablePointer<sockaddr_in6>) in
                    return CFSwapInt16BigToHost(ptr.pointee.sin6_port)
                }
            default:
                assert(false, "Cant retrieve port for this type address")
                return 0
            }
        }
        set {
            switch Int32(self.family) {
            case AF_INET:
                withPointer { (ptr: UnsafeMutablePointer<sockaddr_in>) in
                    ptr.pointee.sin_port = CFSwapInt16HostToBig(newValue)
                }
            case AF_INET6:
                withPointer { (ptr: UnsafeMutablePointer<sockaddr_in6>) in
                    ptr.pointee.sin6_port = CFSwapInt16HostToBig(newValue)
                }
            default:
                assert(false, "Cant set port for this type address")
            }
        }
    }
    
    public var description: String {
        if (Int32(self.storage.ss_family) == AF_INET) {
            var mutableSelf = self
            return mutableSelf.withPointer { (ptr: UnsafeMutablePointer<sockaddr_in>) in
                let address = String(cString: inet_ntoa(ptr.pointee.sin_addr))
                return "\(address):\(self.port)"
            }
        }
        if (Int32(self.storage.ss_family) == AF_INET6) {
            var mutableSelf = self
            return mutableSelf.withPointer { (ptr: UnsafeMutablePointer<sockaddr_in6>) in
                var sin6Addr = ptr.pointee.sin6_addr
                var cString = [Int8](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                inet_ntop(AF_INET6, &sin6Addr, &cString, socklen_t(cString.count));
                let address = String(cString: cString)
                
                return "[\(address)]:\(self.port)"
            }
            
        }
        return "\(self.storage)"
    }
    
    public var data: Data {
        var mutableSelf = self
        return mutableSelf.withPointer { (ptr: UnsafeMutablePointer<UInt8>) in
            return Data(bytes: ptr, count: Int(self.size))
        }
    }
    
    public var ipv4: sockaddr_in {
        assert(self.isIPv4, "It is not an IPv4 address - cannot return IPv4 address data")
        var mutableSelf = self
        return mutableSelf.withPointer { (ptr: UnsafeMutablePointer<sockaddr_in>) in
            return ptr.pointee
        }
    }
    
    public var ipv6: sockaddr_in6 {
        assert(self.isIPv6, "It is not an IPv6 address - cannot return IPv6 address data")
        var mutableSelf = self
        return mutableSelf.withPointer { (ptr: UnsafeMutablePointer<sockaddr_in6>) in
            return ptr.pointee
        }
    }
    
    
    
    init() {}
    
    init<T>(addr: T) {
        assert(MemoryLayout<sockaddr_storage>.size >= MemoryLayout<T>.size, "Address does not fit into sockaddr_storage")
        
        withPointer { (dest: UnsafeMutablePointer<T>) in
            dest.pointee = addr
        }
    }
    
    init(addr: UnsafeRawPointer, size: socklen_t) {
        assert(MemoryLayout<sockaddr_storage>.size >= Int(size), "Address does not fit into sockaddr_storage")
        
        withPointer { (dest: UnsafeMutablePointer<UInt8>) in
            _ = memcpy(dest, addr, Int(size))
        }
    }
    
    init(data: Data) {
        assert(MemoryLayout<sockaddr_storage>.size >= data.count, "Data does not fit into sockaddr_storage")
        
        withPointer { (dest: UnsafeMutablePointer<UInt8>) in
            data.copyBytes(to: dest, count: data.count)
        }
    }
    
    init(bytes: [UInt8]) {
        assert(MemoryLayout<sockaddr_storage>.size >= bytes.count, "Bytes do not fit into sockaddr_storage")
        
        withPointer { (dest: UnsafeMutablePointer<UInt8>) in
            bytes.withUnsafeBufferPointer { buffer in
                _ = memcpy(dest, buffer.baseAddress, bytes.count)
            }
        }
    }
    
    init?(ipv4: String) {
        var addr: in_addr_t = 0
        guard let buffer: [Int8] = ipv4.cString(using: .ascii) else { return nil }
        guard inet_pton(AF_INET, buffer, &addr) != 0 else { return nil }
        
        withPointer { (ptr: UnsafeMutablePointer<sockaddr_in>) in
            ptr.pointee.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            ptr.pointee.sin_family = sa_family_t(AF_INET)
            ptr.pointee.sin_addr = in_addr(s_addr: addr)
        }
    }
    
    
    mutating func withPointer<T, R>(_ block: (UnsafeMutablePointer<T>)->R) -> R {
        let capacity = MemoryLayout<sockaddr_storage>.size / MemoryLayout<T>.size
        return UnsafeMutablePointer(&self.storage).withMemoryRebound(to: T.self, capacity: capacity) { ptr in
            return block(ptr)
        }
    }
}
