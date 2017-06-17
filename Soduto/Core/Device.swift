//
//  Device.swift
//  Soduto
//
//  Created by Admin on 2016-08-13.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import CleanroomLogger

/// Supported device types.
///
/// - Unknown: Device type is not known. Usupported device types default to this.
/// - Dektop: Device is desktop computer.
/// - Laptop: Device is laptop computer.
/// - Phone: Device is a mobile phone.
/// - Tablet: Device is a tablet.
public enum DeviceType: String {
    case Unknown = "unknown"
    case Desktop = "desktop"
    case Laptop = "laptop"
    case Phone = "phone"
    case Tablet = "tablet"
}

/// Errors thrown by Device instances.
///
/// - InvalidConnection: provided connection has wrong state.
public enum DeviceError: Error {
    case InvalidConnection
}

/// Functionality for handling Device notifications.
public protocol DeviceDelegate: class {
    func device(_ device: Device, didChangePairingStatus pairingStatus: PairingStatus)
    func device(_ device: Device, didReceivePairingRequest pairingRequest: PairingRequest)
    func device(_ device: Device, didChangeReachabilityStatus isReachable: Bool)
    func serviceActions(for device: Device) -> [ServiceAction]
}

/// Functionality for handling incoming data packets from devices.
public protocol DeviceDataPacketHandler: class {
    func handleDataPacket(_ dataPacket:DataPacket, fromDevice device:Device, onConnection connection:Connection) -> Bool
}


/// Device class represents a remote device. Multiple connections to the device may be used, 
/// but only one of the same kind (LAN, Bluetooth, etc.)
public class Device: ConnectionDelegate, PairableDelegate, Pairable, CustomStringConvertible {
    
    // MARK: Types
    
    /// Type for unique device identifier
    public typealias Id = String
    
    private struct PendingDataPacket {
        let packet: DataPacket
        let completionHandler: Connection.SendingCompletionHandler?
    }
    
    
    // MARK: Properties
    
    public weak var delegate: DeviceDelegate? = nil
    
    public let id: Id
    public let name: String
    public let type: DeviceType
    public let incomingCapabilities: Set<Service.Capability>
    public let outgoingCapabilities: Set<Service.Capability>
    public let config: DeviceConfiguration
    
    public private(set) var isReachable: Bool = false {
        didSet {
            if oldValue != self.isReachable {
                self.delegate?.device(self, didChangeReachabilityStatus: self.isReachable)
            }
        }
    }
    
    private var connections: [Connection] = [] // Active connections
    private var lingeringConnections: [Connection] = [] // Dismissed connections, waiting to finish its work and completely close
    private var packetHandlers: [DeviceDataPacketHandler] = []
    private var pendingPackets: [PendingDataPacket] = []
    
    
    // MARK: Initialization / Deinitialization
    
    /// Initialize Device with connection object. Device properties are initialized with connection 
    /// identity property values.
    ///
    /// - parameters:
    ///     - connection: Fully initialized (i.e. in Open state) connection to the device.
    ///     - config: Configuration instance for particular device
    ///
    /// - throws:
    ///     `DeviceError.InvalidConnection` if connection state is not `.Open` or identity property is nil.
    ///     `DataPacket.IdentityError` if connections identity property is invalid.
    public init(connection: Connection, config: DeviceConfiguration) throws {
        guard connection.state == .Open else { throw DeviceError.InvalidConnection }
        guard let identity = connection.identity else { throw DeviceError.InvalidConnection }
        
        self.id = try identity.getDeviceId()
        self.name = try identity.getDeviceName()
        self.type = DeviceType(rawValue: try identity.getDeviceType()) ?? DeviceType.Unknown
        self.incomingCapabilities = try identity.getIncomingCapabilities()
        self.outgoingCapabilities = try identity.getOutgoingCapabilities()
        self.config = config
        self.pairingStatus = self.config.isPaired ? .Paired : .Unpaired
        
        self.addConnection(connection)
        
        // update config with lates device name and type
        config.name = self.name
        config.type = self.type
    }
    
    /// Initialize Device only with configuration. This is mostly useful to create device instances for 
    /// unavailable devices
    ///
    /// - parameters:
    ///     - config: Configuration instance for particular device
    public init(config: DeviceConfiguration) {
        self.id = config.deviceId
        self.name = config.name
        self.type = config.type
        self.incomingCapabilities = Set<Service.Capability>()
        self.outgoingCapabilities = Set<Service.Capability>()
        self.config = config
        self.pairingStatus = self.config.isPaired ? .Paired : .Unpaired
    }
    
    deinit {
        self.discardPendingPackets()
    }
    
    
    // MARK Public API
    
    /// Add additional connection to the device. If the device has already contained a connection 
    /// of the same kind, the old one is removed.
    ///
    /// - Parameter connection: Fully initialized (i.e. in Open state) connection to the device.
    public func addConnection(_ connection: Connection) {
        connection.delegate = self
        connection.pairingDelegate = self
        self.connections.append(connection)
        
        // remove connection of the same type if present
        // do it after new connection added to avoid unnecessary device state switches (especially to .Unavailable)
        let index = self.connections.index { c in
            guard c !== connection else { return false }
            return Swift.type(of: c) == Swift.type(of: connection)
        }
        if let index = index {
            let dismissedConnection = self.connections.remove(at: index)
            self.lingeringConnections.append(dismissedConnection)
            dismissedConnection.closeAfterWriting()
        }
        
        self.updatePairingStatus()
        self.updateReachabilityStatus()
    }
    
    /// Register handler for incoming data packets. Most common handler would be Service instances
    public func addDataPacketHandler(_ handler: DeviceDataPacketHandler) {
        self.packetHandlers.append(handler)
    }
    
    /// Register multiple handlers for incoming data packets. Most common handlers would be Service instances
    public func addDataPacketHandlers<S : Sequence>(_ handlers: S) where S.Iterator.Element == DeviceDataPacketHandler {
        for handler in handlers {
            self.addDataPacketHandler(handler)
        }
    }
    
    /// Unregister data packet handler which was registered with such methods as 
    /// `addDataPacketHandler(_:)` or `addDataPacketHandlers(_:)`
    public func removeDataPacketHandler(_ handler: DeviceDataPacketHandler) {
        let index = self.packetHandlers.index { $0 === handler }
        if index != nil {
            self.packetHandlers.remove(at: index!)
        }
    }
    
    /// Return all service actions available to this device
    public func serviceActions() -> [ServiceAction] {
        guard self.pairingStatus == .Paired else { return [] }
        return self.delegate?.serviceActions(for: self) ?? []
    }
    
    /// Send a data packet to remote device. A most appropriate connection for the task
    /// would be chosen automatically. Completion block may be provided - it would be called
    /// when packet is successfully sent. On failure completion handler would not be called -
    /// whole connection would be closed instead.
    public func send(_ packet: DataPacket, whenCompleted: Connection.SendingCompletionHandler? = nil) {
        if let connection = self.connectionForSending() {
            let accepted = connection.send(packet, whenCompleted: whenCompleted)
            if !accepted {
                let pendingPacket = PendingDataPacket(packet: packet, completionHandler: whenCompleted)
                self.pendingPackets.insert(pendingPacket, at: 0)
            }
        }
        else {
            whenCompleted?(false, false)
        }
    }
    
    /// Cleanup all pending to send packets, executing their completion handlers if any.
    public func discardPendingPackets() {
        for pendingPacket in self.pendingPackets {
            pendingPacket.completionHandler?(false, false)
        }
        self.pendingPackets = []
    }
    
    
    // MARK: ConnectionDelegate
    
    public func connection(_ connection: Connection, didSwitchToState state: Connection.State) {
        Log.debug?.message("connection(<\(connection)> didSwitchToState:<\(state)>)")
        switch state {
        case .Closed:
            // Remove closed connection from containing list and reclaim its unsent packets
            // to be sent with another connection.
            // NOTE: Reclaiming unsent packets handle only those packets, that are unsent itself,
            // not the ones that have uploading in progress. However it is ok to remove connections with
            // uploads in progress as upload tasks and connections keep references to each other,
            // so connection will be alive until all uploads are finished and all completion handlers are executed
            if let index = self.connections.index(of: connection) {
                let connection = self.connections.remove(at: index)
                self.reclaimUnsentPackets(from: connection)
                self.updateReachabilityStatus()
            }
            else if let index = self.lingeringConnections.index(of: connection) {
                let connection = self.lingeringConnections.remove(at: index)
                self.reclaimUnsentPackets(from: connection)
            }
            else {
                assertionFailure("Connection not found in device connections list")
            }
        default:
            assertionFailure("Unexpected connection state switch: \(connection) -> \(state)")
        }
    }
    
    public func connection(_ connection: Connection, didSendPacket packet: DataPacket, uploadedPayload: Bool) {
        
    }
    
    public func connection(_ connection: Connection, didReadPacket packet: DataPacket) {
        self.handle(packet: packet, onConnection: connection)
    }
    
    public func connectionCapacityChanged(_ connection: Connection) {
        self.sendPendingPackets()
    }
    
    
    // MARK: PairableDelegate
    
    public func pairable(_ pairable:Pairable, receivedRequest request:PairingRequest) {
        self.delegate?.device(self, didReceivePairingRequest: request)
    }
    
    public func pairable(_ pairable:Pairable, failedWithError error:Error) {
        Log.debug?.message("pairable(<\(pairable)> failedWithError:<\(error)>)")
    }
    
    public func pairable(_ pairable:Pairable, statusChanged status:PairingStatus) {
        self.updatePairingStatus()
    }
    
    
    // MARK: Pairable
    
    /// Not used - present only to comply Pairable protocol
    public var pairingDelegate: PairableDelegate? = nil
    
    public var pairingStatus: PairingStatus {
        didSet {
            if pairingStatus != oldValue {
                self.delegate?.device(self, didChangePairingStatus: self.pairingStatus)
            }
        }
    }
    
    public func requestPairing() {
        if let connection = self.connectionForPairing() {
            if connection.pairingStatus == .RequestedByPeer {
                connection.acceptPairing()
            }
            else {
                connection.requestPairing()
            }
        }
    }
    
    public func acceptPairing() {
        if let connection = self.connectionForPairing(), connection.pairingStatus == .RequestedByPeer {
            connection.acceptPairing()
        }
    }
    
    public func declinePairing() {
        for connection in self.connections {
            switch connection.pairingStatus {
            case .RequestedByPeer:
                connection.declinePairing()
                break
            case .Paired, .Requested:
                connection.unpair()
                break
            default:
                break
            }
        }
    }
    
    public func unpair() {
        for connection in self.connections {
            switch connection.pairingStatus {
            case .Paired, .Requested:
                connection.unpair()
                break
            case .RequestedByPeer:
                connection.declinePairing()
                break
            default:
                break
            }
        }
        
        // Device might be unavailable and no connections present - update status once more to be sure
        self.updatePairingStatus(globalStatus: .Unpaired)
    }
    
    public func updatePairingStatus(globalStatus: PairingStatus) {
        for connection in self.connections {
            connection.updatePairingStatus(globalStatus: globalStatus)
        }
        self.config.isPaired = globalStatus == .Paired
        if !self.config.isPaired {
            self.config.certificate = nil
        }
        self.pairingStatus = globalStatus
    }
    
    
    // MARK: CustomStringConvertible
    
    public var description: String {
        return "<Device:\(self.id):\(self.name)>"
    }
    
    
    // MARK: Private
    
    private func updateReachabilityStatus() {
        self.isReachable = self.connections.count != 0
    }
    
    private func updatePairingStatus() {
        var status: PairingStatus = .Unpaired
        if self.connections.count > 0 {
            for connection in self.connections {
                if connection.pairingStatus == .Paired {
                    status = connection.pairingStatus
                    break
                }
                if (connection.pairingStatus == .Requested || connection.pairingStatus == .RequestedByPeer) &&
                    status == .Unpaired {
                    status = connection.pairingStatus
                }
            }
        }
        else {
            status = self.config.isPaired ? .Paired : .Unpaired
        }
        
        self.updatePairingStatus(globalStatus: status)
    }
    
    /// Choose a connection most appropriate for pairing. Return `nil` if pairing seems inapprorpiate.
    private func connectionForPairing() -> Connection? {
        var bestConnection: Connection? = nil
        for connection in self.connections {
            switch connection.pairingStatus {
            case .Unpaired:
                if bestConnection == nil {
                    bestConnection = connection
                }
                break
            case .RequestedByPeer:
                return connection
            case .Requested:
                return nil
            case .Paired:
                return nil
            }
        }
        return bestConnection
    }
    
    /// Choose a connection most appropriate for sending packets. Connection may be chosen 
    /// according its availability, reliability, speed, etc.
    private func connectionForSending() -> Connection? {
        for connection in self.connections {
            if connection.pairingStatus == .Paired {
                return connection
            }
        }
        return nil
    }
    
    /// Pass received data packet to the handlers, registered with methods such as
    /// `addDataPacketHandler(_:)` or `addDataPacketHandlers(_:)`
    private func handle(packet: DataPacket, onConnection connection: Connection) {
        for handler in self.packetHandlers {
            let handled = handler.handleDataPacket(packet, fromDevice: self, onConnection: connection)
            if handled {
                return
            }
        }
    }
    
    /// Try sending packets from pendingPackets list, send as many as possible until no connection accepts any.
    private func sendPendingPackets() {
        while let pendingPacket = self.pendingPackets.popLast() {
            let connection = self.connectionForSending()
            let accepted = connection?.send(pendingPacket.packet, whenCompleted: pendingPacket.completionHandler) ?? false
            if !accepted {
                self.pendingPackets.append(pendingPacket)
                break
            }
        }
    }
    
    /// Take unsent packets from a closed connection, put them into pendingPackets list and try resend them if possible.
    private func reclaimUnsentPackets(from connection: Connection) {
        assert(connection.state == .Closed, "Connection needs to be closed in order to reclaim its packets: \(connection)")

        let unsentPackets = connection.reclaimUnsentPackets()
        for unsentPacket in unsentPackets {
            let pendingPacket = PendingDataPacket(packet: unsentPacket.dataPacket, completionHandler: unsentPacket.completionHandler)
            self.pendingPackets.append(pendingPacket)
        }

        self.sendPendingPackets()
    }
}
