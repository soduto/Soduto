//
//  ConnectionProvider.swift
//  Migla
//
//  Created by Admin on 2016-08-02.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation


struct PendingConnection {
    let packet: DataPacket
    let address: SocketAddress
}

public class ConnectionProvider: UdpSocketDelegate {
    
    
    private let port: UInt = 1716
    
    private let udpSocket: UdpSocket
    

    
    
    
    init() {
        // Listen for device announcement broadcasts
        self.udpSocket = UdpSocket()
        self.udpSocket.delegate = self
        self.udpSocket.startServer(onPort: port, enableBroadcast:true)
    }
    
    
    
    public func udpSocket(_ socket:UdpSocket, didStartWithAddress address:SocketAddress) {
        Swift.print("udpSocket:didStartWithAddress: \(address)")
    }
    
    public func udpSocket(_ socket:UdpSocket, didSend data:UdpSocket.Buffer, to address:SocketAddress) {
        Swift.print("udpSocket:didSend:to: \(data) \(address)")
    }
    
    public func udpSocket(_ socket:UdpSocket, didFailToSend data:UdpSocket.Buffer, to address:SocketAddress, withError error:UdpSocketError) {
        Swift.print("udpSocket:didFailToSend:to:withError: \(data) \(address) \(error)")
    }
    
    public func udpSocket(_ socket:UdpSocket, didRead data:UdpSocket.Buffer, from address:SocketAddress) {
        var mutableData = data
        let packet = DataPacket(json: &mutableData)
        Swift.print("udpSocket:didRead:from: \(packet) \(address)")
    }
    
    public func udpSocket(_ socket:UdpSocket, didReceiveError error:UdpSocketError) {
        Swift.print("udpSocket:didReceiveError: \(error)")
    }
    
    public func udpSocket(_ socket:UdpSocket, didStopWithError error:UdpSocketError) {
        Swift.print("udpSocket:didStopWithError: \(error)")
    }
    
}
