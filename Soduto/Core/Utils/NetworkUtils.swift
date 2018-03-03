//
//  NetworkUtils.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-11-27.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import CleanroomLogger

public struct NetworkUtils {
    
    // MARK: Types
    
    public enum NetworkError: Error {
        case routeSysctlEstimateFailed
        case routingTableRetrievalFailed
    }
    
    public struct ArpInfo {
        let sin_addr: in_addr
        let ipAddressString: String
        let hwAddressString: String?
    }
    
    public struct LocalAddressInfo {
        let ip: SocketAddress
        let netmask: SocketAddress
        let ipString: String
        let netmaskString: String
    }
    
    
    // Public static methods
    
    public static func accessibleIPv4Addresses() throws -> [ArpInfo] {
        
        // Check required buffer size
        var neededBufferSize: size_t = 0
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        guard sysctl(&mib, 6, nil, &neededBufferSize, nil, 0) >= 0 else { throw NetworkError.routeSysctlEstimateFailed }
        
        var buffer = [UInt8](repeating: 0, count: neededBufferSize)
        
        // Retrieve routing table
        var tableSize: size_t = neededBufferSize
        guard sysctl(&mib, 6, &buffer, &tableSize, nil, 0) >= 0 else { throw NetworkError.routingTableRetrievalFailed }
        
        // Read routing table
        var addresses: [ArpInfo] = []
        buffer.withUnsafeBufferPointer { pointer in
            guard let bufferPtr = UnsafeRawBufferPointer(pointer).baseAddress else { return }
            
            var pos = 0
            while pos < tableSize {
                let rtm = bufferPtr.advanced(by: pos).assumingMemoryBound(to: rt_msghdr.self)
                let sin = UnsafeRawPointer(rtm.advanced(by: 1)).assumingMemoryBound(to: sockaddr_inarp.self)
                let sdl = UnsafeRawPointer(sin.advanced(by: 1)).assumingMemoryBound(to: sockaddr_dl.self)
                
                let sin_addr = sin.pointee.sin_addr
                let ipAddressString = String(cString: inet_ntoa(sin_addr))
                var hwAddressString: String? = nil
                if sdl.pointee.sdl_alen > 0 {
                    var sdlCopy = sdl.pointee
                    let sdlCopyStart = UnsafeRawPointer(UnsafeMutablePointer(&sdlCopy))
                    let sdlCopyDataStart = UnsafeRawPointer(UnsafeMutablePointer(&sdlCopy.sdl_data))
                    let dataOffset = sdlCopyStart.distance(to: sdlCopyDataStart)
                    let sdlDataPtr = UnsafeRawPointer(sdl).advanced(by: dataOffset).assumingMemoryBound(to: UInt8.self)
                    hwAddressString = String(format: "%x:%x:%x:%x:%x:%x",
                        sdlDataPtr.pointee,
                        sdlDataPtr.advanced(by: 1).pointee,
                        sdlDataPtr.advanced(by: 2).pointee,
                        sdlDataPtr.advanced(by: 3).pointee,
                        sdlDataPtr.advanced(by: 4).pointee,
                        sdlDataPtr.advanced(by: 5).pointee)
                }
                
                let info = ArpInfo(sin_addr: sin_addr, ipAddressString: ipAddressString, hwAddressString: hwAddressString)
                addresses.append(info)
                
                pos = pos + Int(rtm.pointee.rtm_msglen)
            }
        }
        
        return addresses
        
        
//        size_t needed;
//        char *host, *lim, *buf, *next;
//        struct rt_msghdr *rtm;
//        struct sockaddr_inarp *sin;
//        struct sockaddr_dl *sdl;
//        extern int h_errno;
//        struct hostent *hp;
//        
//        lim = buf + needed;
//        for (next = buf; next < lim; next += rtm->rtm_msglen) {
//            rtm = (struct rt_msghdr *)next;
//            sin = (struct sockaddr_inarp *)(rtm + 1);
//            sdl = (struct sockaddr_dl *)(sin + 1);
//            if (nflag == 0)
//                hp = gethostbyaddr((caddr_t)&(sin->sin_addr), sizeof sin->sin_addr, AF_INET);
//            else
//                hp = 0;
//            if (hp)
//                host = hp->h_name;
//            else {
//                host = "?";
//                if (h_errno == TRY_AGAIN)
//                    nflag = 1;
//            }
//            printf("%s (%s) at ", host, inet_ntoa(sin->sin_addr));
//            if (sdl->sdl_alen)
//                ether_print((u_char *)LLADDR(sdl));
//            else
//                printf("(incomplete)");
//            if (rtm->rtm_rmx.rmx_expire == 0)
//                printf(" permanent");
//            if (sin->sin_other & SIN_PROXY)
//                printf(" published (proxy only)");
//            if (rtm->rtm_addrs & RTA_NETMASK) {
//                sin = (struct sockaddr_inarp *)(sdl->sdl_len + (char *)sdl);
//                if (sin->sin_addr.s_addr == 0xffffffff)
//                    printf(" published");
//                if (sin->sin_len != 8)
//                    printf("(weird)");
//            }
//            printf("\n");
//        }
    }
    
    public static func hwAddress(for socketAddress: SocketAddress) -> String? {
        guard socketAddress.isIPv4 else { return nil }
        
        let arpInfos = (try? accessibleIPv4Addresses()) ?? []
        for arpInfo in arpInfos {
            if arpInfo.sin_addr.s_addr == socketAddress.ipv4.sin_addr.s_addr {
                return arpInfo.hwAddressString
            }
        }
        return nil
    }
    
    /// Send ping to every possible ip address in local subnet unless subnet is very big. In such
    /// case limit address count to some sane number. Pings are sent as fast as possible without waiting for responses
    public static func pingLocalNetwork() {
        let localAddressInfos = localAddresses()
        for localAddressInfo in localAddressInfos {
            guard localAddressInfo.ip.isIPv4 else { continue } // for now only IPv4 supported
            guard localAddressInfo.netmask.isIPv4 else { continue }
            for i in 1 ... 254 {
                let hostPart = UInt32(i).bigEndian
                let netMask = localAddressInfo.netmask.ipv4.sin_addr.s_addr
                guard (hostPart & netMask) == 0 else { break }
                let networkPrefix = localAddressInfo.ip.ipv4.sin_addr.s_addr & netMask
                var pingAddress = localAddressInfo.ip.ipv4
                pingAddress.sin_addr.s_addr = networkPrefix | hostPart
                
                if let ping = SimplePing(hostAddress: SocketAddress(addr: pingAddress).data) {
                    ping.start()
                    ping.send(with: nil)
                    ping.stop()
                }
            }
        }
    }
    
    // Get the local ip addresses used by this node
    static func localAddresses() -> [LocalAddressInfo] {
        var addresses: [LocalAddressInfo] = []
        
        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>? = nil
        if getifaddrs(&ifaddr) == 0 {
            
            var ptr = ifaddr;
            while ptr != nil {
                
                let flags = Int32((ptr?.pointee.ifa_flags)!)
                var addr = ptr?.pointee.ifa_addr.pointee
                
                // Check for running IPv4, IPv6 interfaces. Skip the loopback interface.
                if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                    if addr?.sa_family == UInt8(AF_INET) || addr?.sa_family == UInt8(AF_INET6) {
                        
                        // Convert interface address to a human readable string:
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if (getnameinfo(&addr!, socklen_t((addr?.sa_len)!), &hostname, socklen_t(hostname.count),
                                        nil, socklen_t(0), NI_NUMERICHOST) == 0) {
                            if let address = String.init(validatingUTF8:hostname) {
                                
                                var net = ptr?.pointee.ifa_netmask.pointee
                                var netmaskName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                                getnameinfo(&net!, socklen_t((net?.sa_len)!), &netmaskName, socklen_t(netmaskName.count),
                                            nil, socklen_t(0), NI_NUMERICHOST)// == 0
                                if let netmask = String.init(validatingUTF8:netmaskName) {
                                    addresses.append(LocalAddressInfo(ip: SocketAddress(addr: addr), netmask: SocketAddress(addr: net), ipString: address, netmaskString: netmask))
                                }
                            }
                        }
                    }
                }
                ptr = ptr?.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        return addresses
    }
    
}
