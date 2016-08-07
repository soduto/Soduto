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
    let cfSocket: CFSocket
}

public class ConnectionProvider: UdpSocketDelegate, ConnectionDelegate {
    
    static public let port: UInt = 1716
    static public let minVersionWithSSLSupport = 6
    
    private let udpSocket: UdpSocket
    private var pendingConnections: Set<Connection> = Set<Connection>()
    
    
    
    init() {
        // Listen for device announcement broadcasts
        self.udpSocket = UdpSocket()
        self.udpSocket.delegate = self
        self.udpSocket.startServer(onPort: ConnectionProvider.port, enableBroadcast:true)
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
        guard let packet = DataPacket(json: &mutableData),
            packet.type == DataPacket.PacketType.Identity.rawValue,
            let port = packet.body["tcpPort"] as? NSNumber else {
            return
        }
        
        Swift.print("udpSocket:didRead:from: \(packet), \(address)")
        
        // create a new address to connect - ip the same as source, port - from packet info
        var connectionAddress = address
        connectionAddress.port = in_port_t(port.uint16Value)
        
        if let connection = Connection(address: connectionAddress, identityPacket: packet) {
            connection.delegate = self
            self.pendingConnections.insert(connection)
        }
    }
    
    public func udpSocket(_ socket:UdpSocket, didReceiveError error:UdpSocketError) {
        Swift.print("udpSocket:didReceiveError: \(error)")
    }
    
    public func udpSocket(_ socket:UdpSocket, didStopWithError error:UdpSocketError) {
        Swift.print("udpSocket:didStopWithError: \(error)")
    }
    
    
    
    public func connection(_ connection: Connection, didSwitchToState state: Connection.State) {
        switch state {
        case .Closed:
            self.pendingConnections.remove(connection)
        case .Open:
            Swift.print("connection:switchedToState: \(connection), \(state)")
            connection.send(DataPacket.identity())
        default:
            assert(false, "Closed or Open connection state expected")
        }
    }
    
    public func connection(_ connection: Connection, didSendPacket packet: DataPacket) {
        Swift.print("connection:didSendPacket: \(connection) \(packet)")
        if connection.protocolVersion >= ConnectionProvider.minVersionWithSSLSupport {
            connection.continueWithSSL()
        }
        else {
            connection.continueWithoutSSL()
        }
    }
    
    public func connection(_ connection: Connection, didReadPacket packet: DataPacket) {
        Swift.print("connection:didReadPacket: \(connection) \(packet)")
    }
    
}
