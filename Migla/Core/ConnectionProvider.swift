//
//  ConnectionProvider.swift
//  Migla
//
//  Created by Admin on 2016-08-02.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import CocoaAsyncSocket
import CleanroomLogger

enum ConnectionProviderError: Error {
    case IdentityAbsent
}

public protocol ConnectionProviderDelegate: class {
    func isNewConnectionNeeded(byProvider provider: ConnectionProvider, deviceId: String) -> Bool
    func connectionProvider(_ provider: ConnectionProvider, didCreateConnection: Connection)
}

public class ConnectionProvider: NSObject, GCDAsyncSocketDelegate, GCDAsyncUdpSocketDelegate, ConnectionDelegate {
    
    static public let udpPort: UInt16 = 1716
    static public let minVersionWithSSLSupport: UInt = 6
    
    public weak var delegate: ConnectionProviderDelegate? = nil
    
    private let config: ConnectionConfiguration
    private let udpSocket: GCDAsyncUdpSocket = GCDAsyncUdpSocket(delegate: nil, delegateQueue: DispatchQueue.main)
    private let tcpSocket: GCDAsyncSocket = GCDAsyncSocket(delegate: nil, delegateQueue: DispatchQueue.main)
    private var pendingConnections: Set<Connection> = Set<Connection>()
    
    
    
    init(config: ConnectionConfiguration) {
        self.config = config
        
        super.init()
        
        self.udpSocket.setDelegate(self)
        self.tcpSocket.delegate = self
    }
    
    public func start() {
        
        // Listen for device announcement broadcasts
        do { try self.udpSocket.enableBroadcast(true) }
        catch { Log.error?.message("Could not enable brodcast for udp socket: \(error)") }
        do { try self.udpSocket.enableReusePort(true) }
        catch { Log.error?.message("Could not enable port reuse for udp socket: \(error)") }
        do {
            try self.udpSocket.bind(toPort: ConnectionProvider.udpPort)
            try self.udpSocket.beginReceiving()
        }
        catch {
            Log.error?.message("Could not start listening for self-announcement broadcasts: \(error)")
        }
        
        // Listen for connections on TCP
        for i: UInt16 in 0..<20 {
            do {
                let port = ConnectionProvider.udpPort + i
                try self.tcpSocket.accept(onPort: port)
                Log.info?.message("Listening on port \(port)")
            }
            catch {}
        }
        
        broadcastAnnouncement()
    }
    
    
    // MARK: Anouncements broadcasting
    
    func broadcastAnnouncement() {
        guard self.tcpSocket.localPort > 0 else { return }
        
        let properties: DataPacket.Body = [
            DataPacket.IdentityProperty.tcpPort.rawValue: Int(self.tcpSocket.localPort) as AnyObject
        ]
        let packet = DataPacket.identityPacket(additionalProperties: properties, config: self.config)
        if let bytes = try? packet.serialize() {
            let data = Data(bytes: bytes)
            
            var address = SocketAddress(ipv4: "255.255.255.255")!
            address.port = ConnectionProvider.udpPort
            self.udpSocket.send(data, toAddress: address.data, withTimeout: 120, tag: Int(packet.id))
            
            // send explicit announcements to known hardware addresses
            let knownDeviceConfigs = self.config.knownDeviceConfigs()
            let accessibleAddresses = (try? NetworkUtils.accessibleIPv4Addresses()) ?? []
            for accessibleAddress in accessibleAddresses {
                guard let accessibleHwAddress = accessibleAddress.hwAddressString else { continue }
                for deviceConfig in knownDeviceConfigs {
                    guard deviceConfig.hwAddresses.contains(accessibleHwAddress) else { continue }
                    guard let deviceAddress = SocketAddress(ipv4: accessibleAddress.ipAddressString) else { continue }
                    var mutableDeviceAddress = deviceAddress
                    mutableDeviceAddress.port = ConnectionProvider.udpPort
                    self.udpSocket.send(data, toAddress: mutableDeviceAddress.data, withTimeout: 120, tag: Int(packet.id))
                    break
                }
            }
        }
    }
    
    
    // MARK: GCDAsyncUdpSocketDelegate
    
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didSendDataWithTag tag: Int) {
        Log.debug?.message("udpSocket(<\(sock)> didSendDataWithTag:<\(tag)>)")
    }
    
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didNotSendDataWithTag tag: Int, dueToError error: Error) {
        Log.debug?.message("udpSocket(<\(sock)> didNotSendDataWithTag:<\(tag)> dueToError:<\(error)>)")
    }
    
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        guard let delegate = self.delegate else { return }
        guard let packet = DataPacket(data: data) else { return }
        guard let port = try? packet.getTCPPort() else { return }
        guard let deviceId = try? packet.getDeviceId() else { return }
        guard delegate.isNewConnectionNeeded(byProvider: self, deviceId: deviceId) else { return }
        
        Log.debug?.message("udpSocket(<\(sock)> didReceive:<<Data>> fromAddress:<\(SocketAddress(data: address))> withFilterContext:<\(packet)>)")
        
        // create a new address to connect - ip the same as source, port - from packet info
        var connectionAddress = SocketAddress(data: address)
        connectionAddress.port = in_port_t(port)
        
        if let connection = Connection(address: connectionAddress, identityPacket: packet, config: self.config) {
            connection.delegate = self
            self.pendingConnections.insert(connection)
            
            // send initial identity packet
            connection.send(DataPacket.identityPacket(config: self.config))
        }
    }
    
    public func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error) {
        Log.debug?.message("udpSocketDidClose(<\(sock)> withError:<\(error)>)")
    }
    
    
    // MARK: GCDAsyncSocketDelegate
    
    public func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        Log.debug?.message("socket(<\(sock)> didAcceptNewSocket:<\(newSocket)>)")
        
        if let connection = Connection(socket: newSocket, config: self.config) {
            connection.delegate = self
            self.pendingConnections.insert(connection)
            
            // read initial identity packet
            connection.readOnePacket()
        }
    }
    
    
    // MARK: ConnectionDelegate
    
    public func connection(_ connection: Connection, didSwitchToState state: Connection.State) {
        Log.debug?.message("connection(<\(connection)> switchedToState:<\(state)>)")
        switch state {
        case .Closed:
            self.pendingConnections.remove(connection)
        case .Open:
            connection.readPackets()
            if let delegate = self.delegate {
                self.pendingConnections.remove(connection)
                delegate.connectionProvider(self, didCreateConnection: connection)
            }
            else {
                Log.error?.message("No connection provider delegate to take new connection - closing");
                connection.close()
            }
        default:
            assert(false, "Closed or Open connection state expected")
        }
    }
    
    public func connection(_ connection: Connection, didSendPacket packet: DataPacket, uploadedPayload: Bool) {
        Log.debug?.message("connection(<\(connection)> didSendPacket:<\(packet)>)")
        
        do {
            guard let identity = connection.identity else { throw ConnectionProviderError.IdentityAbsent }
            let protocolVersion = try identity.getProtocolVersion()
            if protocolVersion >= ConnectionProvider.minVersionWithSSLSupport {
                // Beware that securing as server while connection initiated by self
                connection.secureServer()
            }
            connection.finishInitialization()
        }
        catch {
            Log.error?.message("Failed to initialize connection: \(error)")
            connection.close()
        }
    }
    
    public func connection(_ connection: Connection, didReadPacket packet: DataPacket) {
        Log.debug?.message("connection(<\(connection)> didReadPacket:<\(packet)>)")
        
        // The only packet we are waiting for is first identity packet to initialize connection with
        do {
            try connection.applyIdentity(packet: packet)
            let protocolVersion = try packet.getProtocolVersion()
            if protocolVersion >= ConnectionProvider.minVersionWithSSLSupport {
                // Beware that securing as client while connection initiated by the peer
                connection.secureClient()
            }
            connection.finishInitialization()
        }
        catch {
            Log.error?.message("Failed to initialize connection: \(error)")
            connection.close()
        }
    }
    
}
