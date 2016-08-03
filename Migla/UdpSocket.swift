//
//  UdpSocket.swift
//  Migla
//
//  Created by Admin on 2016-07-12.
//  Copyright © 2016 Migla. All rights reserved.
//

// Code adopted from https://developer.apple.com/library/mac/samplecode/UDPEcho/Listings/UDPEcho_m.html#//apple_ref/doc/uid/DTS40009660-UDPEcho_m-DontLinkElementID_5

import Foundation
import CFNetwork

public struct UdpSocketError: Error {
    let domain: String
    let code: Int32
    let userInfo: UnsafePointer<Void>?
}

public protocol UdpSocketDelegate {
    func udpSocket(_ socket:UdpSocket, didStartWithAddress:UdpSocket.Address)
    func udpSocket(_ socket:UdpSocket, didSend:UdpSocket.Buffer, to:UdpSocket.Address)
    func udpSocket(_ socket:UdpSocket, didFailToSend:UdpSocket.Buffer, to:UdpSocket.Address, withError:UdpSocketError)
    func udpSocket(_ socket:UdpSocket, didRead:UdpSocket.Buffer, from:UdpSocket.Address)
    func udpSocket(_ socket:UdpSocket, didReceiveError:UdpSocketError)
    func udpSocket(_ socket:UdpSocket, didStopWithError:UdpSocketError)
}

public class UdpSocket {
    
    public typealias Address = [UInt8]
    public typealias Buffer = [UInt8]
    
    public var delegate: UdpSocketDelegate?
    
    private(set) public var hostName: String?
    private(set) public var hostAddress: Address?
    private(set) public var port: UInt = 0
    
    public var isServer: Bool {
        return self.hostName == nil
    }
    
    private var cfHost: CFHost?
    private var cfSocket: CFSocket?
    
    deinit {
        self.stop()
    }
    
    
    
    public func send(data: Buffer) {
        
        // If you call send(data:) on a object in server mode or an object in client mode
        // that's not fully set up (hostAddress is nil), we just ignore you.
        
        if self.isServer || self.hostAddress == nil {
            assert(false)
        }
        else {
            self.send(data:data, to:nil)
        }
    }
    
    public func send(data: Buffer, to address: Address?) {
        
        // address is nil in the client case, whereupon the
        // data is automatically sent to the hostAddress by virtue of the fact
        // that the socket is connected to that address.
        
        assert((address != nil) == self.isServer)
        assert((address == nil) || (address?.count <= sizeof(sockaddr_storage.self)))
        
        let sock = CFSocketGetNative(self.cfSocket)
        assert(sock >= 0)
        
        let dataPtr: UnsafePointer<Void> = castToPointer(array: data)
        let addr: Address
        let addrPtr: UnsafePointer<sockaddr>?
        let addrLen: socklen_t
        if let address = address {
            addr = address
            addrPtr = castToPointer(array: address)
            addrLen = socklen_t(address.count)
        }
        else {
            assert(self.hostAddress != nil)
            if let address = self.hostAddress {
                addr = address
                addrPtr = nil
                addrLen = 0
            }
            else {
                // just to silent compiler
                addr = Address()
                addrPtr = nil
                addrLen = 0
            }
        }
        
        let bytesWritten = sendto(sock, dataPtr, data.count, 0, addrPtr, addrLen)
        let err: Int32
        if bytesWritten < 0 {
            err = errno
        }
        else if bytesWritten == 0 {
            err = EPIPE
        }
        else {
            // We ignore any short writes, which shouldn't happen for UDP anyway.
            assert(bytesWritten == data.count)
            err = 0
        }
        
        if let delegate = self.delegate {
            if err == 0 {
                delegate.udpSocket(self, didSend: data, to: addr)
            }
            else {
                let error = UdpSocketError(domain: NSPOSIXErrorDomain, code: err, userInfo: nil)
                delegate.udpSocket(self, didFailToSend: data, to: addr, withError:error)
            }
        }
    }
    
    public func stop() {
        self.hostName = nil
        self.hostAddress = nil
        self.port = 0
        
        self.stopHostResolution()
        
        if let cfSocket = self.cfSocket {
            CFSocketInvalidate(cfSocket)
            self.cfSocket = nil
        }
    }
    
    public func startServer(onPort port:UInt, enableBroadcast:Bool) {
        assert(port > 0 && port < 65536)
        assert(self.port == 0)     // don't try and start a started object
        
        do {
            // Create a fully configured socket.
            try self.setupSocket(connectedToAddress: nil, port: port, enableBroadcast: enableBroadcast)
            
            self.port = port
            
            if let delegate = self.delegate {
                let localAddressData = CFSocketCopyAddress(self.cfSocket) as Data
                
                let localAddress = localAddressData.withUnsafeBytes {
                    Array(UnsafeBufferPointer<UInt8>(start: $0, count: localAddressData.count))
                }
                delegate.udpSocket(self, didStartWithAddress:localAddress)
            }
        }
        catch let error as UdpSocketError {
            self.stop(withError: error)
        }
        catch {
            self.stop(withError: UdpSocketError(domain:"", code:0, userInfo: nil))
        }
    }
    
    public func startClient(connectedTo hostName:String, onPort port:UInt) {
        
        assert(!hostName.isEmpty)
        assert(port > 0 && port < 65536)
        assert(self.port == 0);     // don't try and start a started object
        assert(self.cfHost == nil)
        
        self.cfHost = CFHostCreateWithName(nil, hostName).takeRetainedValue()
        assert(self.cfHost != nil)
        let cfHost = self.cfHost!
        
        var context = CFHostClientContext(version: 0, info: bridge(obj: self), retain: nil, release: nil, copyDescription: nil)
        CFHostSetClient(cfHost, HostResolveCallback, &context)
        CFHostScheduleWithRunLoop(cfHost, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode as! CFString)
        
        var streamError = CFStreamError()
        let success = CFHostStartInfoResolution(cfHost, .addresses, &streamError)
        if success {
            self.hostName = hostName
            self.port = port
            // ... continue in HostResolveCallback
        }
        else {
            self.stop(withStreamError:streamError)
        }
    }
    
    
    
    private func read() {
        // Called by the CFSocket read callback to actually read and process data
        // from the socket.
        
        let sock = CFSocketGetNative(self.cfSocket)
        assert(sock >= 0)
        
        var buffer = Buffer(repeating: 0, count: 65536)
        var addr = sockaddr_storage()
        let addrPtr: UnsafeMutablePointer<sockaddr> = cast(pointer: &addr)
        var addrLen = socklen_t(sizeofValue(addr))
        
        let bytesRead = recvfrom(sock, &buffer, buffer.count, 0, addrPtr, &addrLen)
        let err: Int32
        if bytesRead < 0 {
            err = errno
            
        }
        else if bytesRead == 0 {
            err = EPIPE
        }
        else {
            err = 0
            
            let dataObj = Buffer(buffer.prefix(bytesRead))
            let addrObj = Address(UnsafeBufferPointer(start: cast(pointer: &addr), count: Int(addrLen)))
            
            // Tell the delegate about the data.
            if let delegate = self.delegate {
                delegate.udpSocket(self, didRead: dataObj, from: addrObj)
            }
        }
        
        // If we got an error, tell the delegate
        if err != 0, let delegate = self.delegate {
            let error = UdpSocketError(domain: NSPOSIXErrorDomain, code: err, userInfo: nil)
            delegate.udpSocket(self, didReceiveError: error)
        }
    }
    
    private func setupSocket(connectedToAddress address:Address?, port:UInt, enableBroadcast:Bool) throws {
        // Sets up the CFSocket in either client or server mode.  In client mode,
        // address contains the address that the socket should be connected to.
        // The address contains zero port number, so the port parameter is used instead.
        // In server mode, address is nil and the socket is bound to the wildcard
        // address on the specified port.
    
        assert((address == nil) == self.isServer)
        assert((address == nil) || (address?.count <= sizeof(sockaddr_storage.self)))
        assert(port < 65536)
        assert(self.cfSocket == nil)
    
        // Create the UDP socket itself.  First try IPv6 and, if that's not available, revert to IPv6.
        //
        // IMPORTANT: Even though we're using IPv6 by default, we can still work with IPv4 due to the
        // miracle of IPv4-mapped addresses.
    
        var err: Int32 = 0
    
        var sock = socket(AF_INET6, SOCK_DGRAM, 0)
        let socketFamily: Int32
        if sock >= 0 {
            socketFamily = AF_INET6
        }
        else {
            sock = socket(AF_INET, SOCK_DGRAM, 0)
            if sock >= 0 {
                socketFamily = AF_INET
            }
            else {
                err = errno
                socketFamily = 0
            }
        }
    
        // Bind or connect the socket, depending on whether we're in server or client mode.
        if err == 0 {
    
            var addr = sockaddr_storage()
            let addr4: UnsafeMutablePointer<sockaddr_in> = cast(pointer: &addr)
            let addr6: UnsafeMutablePointer<sockaddr_in6> = cast(pointer: &addr)
    
            memset(&addr, 0, sizeofValue(addr))
            
            if let address = address {
                // Client mode. Set up the address on the caller-supplied address and port
                // number. Also, if the address is IPv4 and we created an IPv6 socket,
                // convert the address to an IPv4-mapped address.
                
                let addressPtr: UnsafePointer<UInt8> = castToPointer(array: address)
                if address.count > sizeofValue(addr) {
                    assert(false) // very weird
                    memcpy(&addr, addressPtr, sizeofValue(addr))
                }
                else {
                    memcpy(&addr, addressPtr, address.count)
                }
                
                if addr.ss_family == sa_family_t(AF_INET) {
                    
                    if socketFamily == AF_INET6 {
                        // Convert IPv4 address to IPv4-mapped-into-IPv6 address.
                        let ipv4Addr = addr4.pointee.sin_addr
                        
                        addr6.pointee.sin6_len = UInt8(sizeofValue(addr6.pointee))
                        addr6.pointee.sin6_family = sa_family_t(AF_INET6)
                        addr6.pointee.sin6_port = CFSwapInt16HostToBig(in_port_t(port))
                        addr6.pointee.sin6_addr.__u6_addr.__u6_addr32 = (
                            0,
                            0,
                            CFSwapInt32HostToBig(0xffff),
                            ipv4Addr.s_addr
                        )
                    } else {
                        addr4.pointee.sin_port = CFSwapInt16HostToBig(in_port_t(port))
                    }
                    
                }
                else {
                    assert(addr.ss_family == sa_family_t(AF_INET6))
                    addr6.pointee.sin6_port = CFSwapInt16HostToBig(in_port_t(port))
                }
                
                if (addr.ss_family == sa_family_t(AF_INET)) && (socketFamily == AF_INET6) {
                    addr6.pointee.sin6_len = UInt8(sizeofValue(addr6.pointee))
                    addr6.pointee.sin6_port = CFSwapInt16HostToBig(in_port_t(port))
                    addr6.pointee.sin6_addr = in6addr_any
                }
                
            }
            else {
                // Server mode. Set up the address based on the socket family of the socket
                // that we created, with the wildcard address and the caller-supplied port number.
                
                addr.ss_family = sa_family_t(socketFamily)
                
                if socketFamily == AF_INET {
                    addr4.pointee.sin_len = UInt8(sizeofValue(addr4.pointee))
                    addr4.pointee.sin_port = CFSwapInt16HostToBig(in_port_t(port))
                    addr4.pointee.sin_addr.s_addr = UInt32(0x00000000)    // INADDR_ANY = (u_int32_t)0x00000000 ----- <netinet/in.h>
                }
                else {
                    assert(socketFamily == AF_INET6)
                    addr6.pointee.sin6_len = UInt8(sizeofValue(addr6.pointee))
                    addr6.pointee.sin6_port = CFSwapInt16HostToBig(in_port_t(port))
                    addr6.pointee.sin6_addr = in6addr_any
                }
            }
            
            if enableBroadcast {
                var on: UInt32 = 1
                err = setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(sizeofValue(on)))
            }
    
            if err == 0 {
                let addrPtr: UnsafePointer<sockaddr>! = cast(pointer: &addr)
                if address != nil {
                    err = connect(sock, addrPtr, socklen_t(addr.ss_len))
                }
                else {
                    err = bind(sock, addrPtr, socklen_t(addr.ss_len))
                }
        
                if err < 0 {
                    err = errno
                }
            }
        }
    
        // From now on we want the socket in non-blocking mode to prevent any unexpected
        // blocking of the main thread.  None of the above should block for any meaningful
        // amount of time.
        if err == 0 {
            let flags = fcntl(sock, F_GETFL)
            err = fcntl(sock, F_SETFL, flags | O_NONBLOCK)
            if err < 0 {
                err = errno
            }
        }
    
        // Wrap the socket in a CFSocket that's scheduled on the runloop.
        if err == 0 {
            var context = CFSocketContext(version: 0, info: bridge(obj: self), retain: nil, release: nil, copyDescription: nil)
            self.cfSocket = CFSocketCreateWithNative(nil, sock, CFSocketCallBackType.readCallBack.rawValue, SocketReadCallback, &context);
    
            // The socket will now take care of cleaning up our file descriptor.
            assert(CFSocketGetSocketFlags(self.cfSocket) & kCFSocketCloseOnInvalidate == kCFSocketCloseOnInvalidate)
            sock = -1
    
            let rls = CFSocketCreateRunLoopSource(nil, self.cfSocket, 0)
            assert(rls != nil)
    
            CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, CFRunLoopMode.defaultMode)
        }
    
        // Handle any errors.
        if sock != -1 {
            let junk = close(sock)
            assert(junk == 0)
        }
        assert((err == 0) == (self.cfSocket != nil))
        if self.cfSocket == nil {
            throw UdpSocketError(domain:"", code: err, userInfo: nil)
        }
    }
    
    private func hostResolutionDone() {
        // Called by our CFHost resolution callback (HostResolveCallback) when host
        // resolution is complete.  We find the best IP address and create a socket
        // connected to that.
    
        assert(self.port != 0)
        assert(self.cfHost != nil)
        assert(self.cfSocket == nil)
        assert(self.hostAddress == nil)
        
        var err: UdpSocketError? = nil
    
        // Walk through the resolved addresses looking for one that we can work with.
        var resolved: DarwinBoolean = false
        let resolvedAddresses = CFHostGetAddressing(self.cfHost!, &resolved)?.takeRetainedValue() as? [AnyObject] as? [CFData]
        if resolved.boolValue, let resolvedAddresses = resolvedAddresses {
            
            for addressData in resolvedAddresses {
    
                let address = Address(UnsafeBufferPointer<UInt8>(start: CFDataGetBytePtr(addressData), count: CFDataGetLength(addressData)))
                let addrPtr: UnsafePointer<sockaddr> = castToPointer(array: address)
                let addrLen = address.count
                assert(addrLen >= sizeof(sockaddr.self))
                
                // Try to create a connected CFSocket for this address.  If that fails,
                // we move along to the next address. If it succeeds, we're done.
                if (addrPtr.pointee.sa_family == sa_family_t(AF_INET)) || (addrPtr.pointee.sa_family == sa_family_t(AF_INET6)) {
                    do {
                        try self.setupSocket(connectedToAddress: address, port: self.port, enableBroadcast: true)
                        
                        let hostAddressData = CFSocketCopyPeerAddress(self.cfSocket)
                        assert(hostAddress != nil)
                        
                        self.hostAddress = Address(UnsafeBufferPointer<UInt8>(start: CFDataGetBytePtr(hostAddressData), count: CFDataGetLength(hostAddressData)))
                        
                        break
                    }
                    catch let error as UdpSocketError {
                        err = error
                    }
                    catch {
                        err = UdpSocketError(domain: "", code: 0, userInfo: nil)
                    }
                }
            }
        }
    
        // If we didn't get an address and didn't get an error, synthesise a host not found error.
        if (self.hostAddress == nil) && (err == nil) {
            err = UdpSocketError(domain: kCFErrorDomainCFNetwork as String, code:Int32(CFNetworkErrors.cfHostErrorHostNotFound.rawValue), userInfo:nil)
        }
    
        if let err = err {
            self.stop(withError:err)
        }
        else {
            // We're done resolving, so shut that down.
            self.stopHostResolution()
    
            // Tell the delegate that we're up.
            if let delegate = self.delegate, let hostAddress = self.hostAddress {
                delegate.udpSocket(self, didStartWithAddress: hostAddress)
            }
        }
    }
    
    private func stopHostResolution() {
        // Called to stop the CFHost part of the object, if it's still running.
        
        if let cfHost = self.cfHost {
            CFHostSetClient(cfHost, nil, nil)
            CFHostCancelInfoResolution(cfHost, .addresses)
            CFHostUnscheduleFromRunLoop(cfHost, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode as! CFString)
            self.cfHost = nil
        }
    }
    
    private func stop(withError error:UdpSocketError) {
        // Stops the object, reporting the supplied error to the delegate.
        
        self.stop()
        self.delegate?.udpSocket(self, didStopWithError: error)
    }
    
    private func stop(withStreamError streamError:CFStreamError) {
        // Stops the object, reporting the supplied error to the delegate.
    
        var userInfo: [NSObject:AnyObject]? = nil
        if streamError.domain == Int(kCFStreamErrorDomainNetDB) {
            userInfo = [kCFGetAddrInfoFailureKey: Int(streamError.error)]
        } else {
            userInfo = nil;
        }
        
        let error = UdpSocketError(domain: kCFErrorDomainCFNetwork as String, code: CFNetworkErrors.cfHostErrorUnknown.rawValue, userInfo: &userInfo)
        self.stop(withError:error)
    }

}



func bridge<T : AnyObject>(obj : T) -> UnsafeMutablePointer<Void> {
    return UnsafeMutablePointer<Void>(Unmanaged.passUnretained(obj).toOpaque())
    // return unsafeAddressOf(obj) // ***
}

func bridge<T : AnyObject>(ptr : UnsafePointer<Void>) -> T {
    return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
    // return unsafeBitCast(ptr, T.self) // ***
}

func cast<T,U>(pointer: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<U> {
    return unsafeBitCast(pointer, to: UnsafeMutablePointer<U>.self)
}

func cast<T,U>(pointer: UnsafePointer<T>) -> UnsafePointer<U> {
    return unsafeBitCast(pointer, to: UnsafePointer<U>.self)
}

func castToMutablePointer<T,U>(array: Array<T>) -> UnsafeMutablePointer<U> {
    return array.withUnsafeBufferPointer({ (ptr:UnsafeBufferPointer<T>) -> UnsafeMutablePointer<U> in
        return unsafeBitCast(ptr, to: UnsafeMutablePointer<U>.self)
    })
}

func castToPointer<T,U>(array: Array<T>) -> UnsafePointer<U> {
    return array.withUnsafeBufferPointer({ (ptr:UnsafeBufferPointer<T>) -> UnsafePointer<U> in
        return unsafeBitCast(ptr, to: UnsafePointer<U>.self)
    })
}



func SocketReadCallback(socket: CFSocket?, callbackType:CFSocketCallBackType, address:CFData?, data:UnsafePointer<Void>?, info:UnsafeMutablePointer<Void>?) {
    
    // This stand-alone routine is called by CFSocket when there's data waiting on our
    // UDP socket. It just redirects the call to UdpSocket instance that owns the socked.
    
    assert(info != nil)
    assert(callbackType == .readCallBack)
    assert(address == nil)
    assert(data == nil)
    
    if let info = info {
        let udpSocket: UdpSocket = bridge(ptr: info)
        
        assert(socket === udpSocket.cfSocket)
        
        udpSocket.read()
    }
    
}

func HostResolveCallback(host:CFHost, typeInfo:CFHostInfoType, error:UnsafePointer<CFStreamError>?, info:UnsafeMutablePointer<Void>?) {

    // This C routine is called by CFHost when the host resolution is complete.
    // It just redirects the call to the appropriate Objective-C method.
    
    assert(info != nil)
    assert(typeInfo == .addresses)
    
    if let info = info {
        let udpSocket: UdpSocket = bridge(ptr: info)
        
        assert(host === udpSocket.cfHost)
        
        if let err = error, err.pointee.domain != 0 {
            udpSocket.stop(withStreamError:err.pointee)
        }
        else {
            udpSocket.hostResolutionDone()
        }
    }
}

