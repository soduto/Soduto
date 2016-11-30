//
//  NetworkUtils.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-11-27.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public struct NetworkUtils {
    
    // MARK: Types
    
    public enum NetworkError: Error {
        case routeSysctlEstimateFailed
        case routingTableRetrievalFailed
    }
    
    public struct ArpInfo {
        
    }
    
    
    // Public static methods
    
    public static func accessibleAddresses() throws -> [ArpInfo] {
        
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
                
                let ipAddressString = String(cString: inet_ntoa(sin.pointee.sin_addr))
                var hwAddressString: String? = nil
                if sdl.pointee.sdl_alen > 0 {
                    var sdlCopy = sdl.pointee
                    let sdlCopyStart: UnsafePointer<UInt8> = cast(pointer: &sdlCopy)
                    let sdlCopyDataStart: UnsafePointer<UInt8> = cast(pointer: &sdlCopy.sdl_data)
                    let dataOffset = sdlCopyStart.distance(to: sdlCopyDataStart)
                    let sdlDataPtr = UnsafeRawPointer(sdl).advanced(by: dataOffset).assumingMemoryBound(to: UInt8.self)
                    hwAddressString = String(format: "%x:%x:%x:%x:%x:%x",
                        sdlDataPtr.pointee,
                        sdlDataPtr.advanced(by: 1).pointee,
                        sdlDataPtr.advanced(by: 2).pointee,
                        sdlDataPtr.advanced(by: 3).pointee,
                        sdlDataPtr.advanced(by: 4).pointee,
                        sdlDataPtr.advanced(by: 5).pointee)
                    
//                    let caddr caddr_t =sdl.pointee.sdl_data
//                    ((caddr_t)((s)->sdl_data + (s)->sdl_nlen))
//                    let lladdr = LLADDR(sdl.pointee)
//                    String(format: "%x:%x:%x:%x:%x:%x", cp[0], cp[1], cp[2], cp[3], cp[4], cp[5])
                }
                
                Swift.print("Address: \(ipAddressString) -> \(hwAddressString)")
                
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
    
}
