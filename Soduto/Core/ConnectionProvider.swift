//
//  ConnectionProvider.swift
//  Soduto
//
//  Created by Admin on 2016-08-02.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import Cocoa
import CocoaAsyncSocket
import CleanroomLogger
import Reachability

enum ConnectionProviderError: Error {
    case IdentityAbsent
}

public protocol ConnectionProviderDelegate: class {
    func isNewConnectionNeeded(byProvider provider: ConnectionProvider, deviceId: String) -> Bool
    func connectionProvider(_ provider: ConnectionProvider, didCreateConnection: Connection)
}

public class ConnectionProvider: NSObject, GCDAsyncSocketDelegate, GCDAsyncUdpSocketDelegate, ConnectionDelegate {
    
    static public let udpPort: UInt16 = 1716
    static public let minTcpPort: UInt16 = 1716
    static public let maxTcpPort: UInt16 = 1764
    static public let minVersionWithSSLSupport: UInt = 6
    static public let minAnnouncementInterval: TimeInterval = 30.0
    static public let broadcastAnnouncementNotification: Notification.Name = Notification.Name(rawValue: "com.soduto.ConnectionProvider.broadcastAnnouncement")
    
    public weak var delegate: ConnectionProviderDelegate? = nil
    
    private let config: ConnectionConfiguration
    private let reachability: Reachability? = Reachability()
    private let udpSocket: GCDAsyncUdpSocket = GCDAsyncUdpSocket(delegate: nil, delegateQueue: DispatchQueue.main)
    private let tcpSocket: GCDAsyncSocket = GCDAsyncSocket(delegate: nil, delegateQueue: DispatchQueue.main)
    private var pendingConnections: Set<Connection> = Set<Connection>()
    private var isStarted: Bool = false
    private var lastAnnouncementTime: TimeInterval = 0.0
    private var announcementTimer: Timer? = nil
    
    
    
    init(config: ConnectionConfiguration) {
        self.config = config
        
        super.init()
        
        self.reachability?.whenReachable =  { [unowned self] _ in self.becameReachable() }
        self.reachability?.whenUnreachable =  { [unowned self] _ in self.becameUnreachable() }
        do {
            try self.reachability?.startNotifier()
        }
        catch {
            Log.error?.message("Failed to start monitoring network reachability: \(error)")
        }
        self.udpSocket.setDelegate(self)
        self.tcpSocket.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(broadcastAnnouncement), name: ConnectionProvider.broadcastAnnouncementNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
            Log.info?.message("Listening for UDP broadcasts on port \(self.udpSocket.localPort())")
        }
        catch {
            Log.error?.message("Could not start listening for self-announcement broadcasts: \(error)")
        }
        
        // Listen for connections on TCP
        for port: UInt16 in ConnectionProvider.minTcpPort...ConnectionProvider.maxTcpPort {
            do {
                try self.tcpSocket.accept(onPort: port)
                Log.info?.message("Listening for TCP connections on port \(self.tcpSocket.localPort)")
            }
            catch {}
        }
        if self.tcpSocket.isDisconnected {
            Log.error?.message("Failed to start listening TCP connections on ports in range \(ConnectionProvider.minTcpPort)-\(ConnectionProvider.maxTcpPort)")
        }
        
        self.isStarted = true
        
        broadcastAnnouncement()
        
        // Speculative broadcasts after some intervals.
        // When broadcasting imediately after internet connection becomes available, ARP table may be incomplete and not all known devices may be detected. After some time, theese undetected devices may become known and may receive the announcement
        _ = Timer.compatScheduledTimer(withTimeInterval: 40.0, repeats: false) { _ in self.broadcastAnnouncement() }
        _ = Timer.compatScheduledTimer(withTimeInterval: 80.0, repeats: false) { _ in self.broadcastAnnouncement() }
        _ = Timer.compatScheduledTimer(withTimeInterval: 120.0, repeats: false) { _ in self.broadcastAnnouncement() }
    }
    
    public func stop() {
        self.isStarted = false
        self.udpSocket.close()
        self.tcpSocket.disconnect()
    }
    
    public func restart() {
        guard self.isStarted else { return }
        self.stop()
        self.start()
    }
    
    
    // MARK: Announcements broadcasting
    
    @objc public dynamic func broadcastAnnouncement() {
        guard self.isStarted else { return }
        guard self.tcpSocket.localPort > 0 else { return }
        guard self.announcementTimer == nil else { return }
        
        if self.lastAnnouncementTime + ConnectionProvider.minAnnouncementInterval < CACurrentMediaTime() {
            
            Log.debug?.message("Broadcasting self-announcement")
            
            // Try to fill ARP table with all reachable addresses
            NetworkUtils.pingLocalNetwork()
            
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
            
            self.lastAnnouncementTime = CACurrentMediaTime()
        }
        else {
            self.announcementTimer = Timer.compatScheduledTimer(withTimeInterval: ConnectionProvider.minAnnouncementInterval, repeats: false) { _ in
                self.announcementTimer = nil
                self.broadcastAnnouncement()
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
            _ = connection.send(DataPacket.identityPacket(config: self.config))
        }
    }
    
    public func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error) {
//        Log.debug?.message("udpSocketDidClose(<\(sock)> withError:<\(error)>)")
    }
    
    
    // MARK: GCDAsyncSocketDelegate
    
    public func newSocketQueueForConnection(fromAddress address: Data, on sock: GCDAsyncSocket) -> DispatchQueue? {
        return DispatchQueue.main
    }
    
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
            if let delegate = self.delegate {
                connection.readPackets()
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
    
    public func connectionCapacityChanged(_ connection: Connection) { }
    
    
    // MARK: Private methrod
    
    private func becameReachable() {
        Log.debug?.message("Became reachable")
        self.restart()
    }
    
    private func becameUnreachable() {
        Log.debug?.message("Became unreachable")
    }
    
}
