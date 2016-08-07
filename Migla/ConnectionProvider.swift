//
//  ConnectionProvider.swift
//  Migla
//
//  Created by Admin on 2016-08-02.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import CocoaAsyncSocket


struct PendingConnection {
    let packet: DataPacket
    let address: SocketAddress
    let cfSocket: CFSocket
}

public class ConnectionProvider: NSObject, GCDAsyncSocketDelegate, GCDAsyncUdpSocketDelegate, ConnectionDelegate {
    
    static public let udpPort: UInt16 = 1716
    static public let minVersionWithSSLSupport = 6
    
    private let udpSocket: GCDAsyncUdpSocket = GCDAsyncUdpSocket(delegate: nil, delegateQueue: DispatchQueue.main)
    private let tcpSocket: GCDAsyncSocket = GCDAsyncSocket(delegate: nil, delegateQueue: DispatchQueue.main)
    private var pendingConnections: Set<Connection> = Set<Connection>()
    
    
    
    override init() {
        
        super.init()
        
        // Listen for device announcement broadcasts
        self.udpSocket.setDelegate(self)
        do { try self.udpSocket.enableBroadcast(true) }
        catch { Swift.print("Could not enable brodcast for udp socket: \(error)") }
        do {
            try self.udpSocket.bind(toPort: ConnectionProvider.udpPort)
            try self.udpSocket.beginReceiving()
        }
        catch {
            Swift.print("Could not start listening for self-announcement broadcasts: \(error)")
        }
    }
    
    
    
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: AnyObject?) {
        guard let packet = DataPacket(data: data) else { return }
        guard packet.type == DataPacket.PacketType.Identity.rawValue else { return }
        guard let port = packet.body["tcpPort"] as? NSNumber else { return }
        
        Swift.print("udpSocket:didReceive:fromAddress:withFilterContext: \(sock), \(data), \(address), \(filterContext)")
        
        // create a new address to connect - ip the same as source, port - from packet info
        var connectionAddress = SocketAddress(data: address)
        connectionAddress.port = in_port_t(port.uint16Value)
        
        if let connection = Connection(address: connectionAddress, identityPacket: packet) {
            connection.delegate = self
            self.pendingConnections.insert(connection)
        }
    }
    
    public func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error) {
        Swift.print("udpSocketDidClose:withError: \(sock), \(error)")
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
