//
//  Device.swift
//  Migla
//
//  Created by Admin on 2016-08-13.
//  Copyright © 2016 Migla. All rights reserved.
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
    func device(_ device: Device, didChangeState state: Device.State)
    func device(_ device: Device, didReceivePairingRequest pairingRequest: PairingRequest)
    func serviceActions(for device: Device) -> [ServiceAction]
}

/// Functionality for handling incoming data packets from devices.
public protocol DeviceDataPacketHandler: class {
    func handleDataPacket(_ dataPacket:DataPacket, fromDevice device:Device, onConnection connection:Connection) -> Bool
}


/// Device class represents a remote device. Multiple connections to the device may be used, 
/// but only one of the same kind (LAN, Bluetooth, etc.)
public class Device: ConnectionDelegate, PairableDelegate, Pairable {
    
    // MARK: Types
    
    /// Type for unique device identifier
    public typealias Id = String
    
    /// State of the Device instance.
    ///
    /// - Unavailable: Device is unreachable.
    /// - Unpaired: Device is reachable but not trusted (unpaired).
    /// - Paired: Device is reachable and trusted (paired).
    public enum State {
        case unavailable
        case unpaired
        case pairing
        case paired
    }
    
    
    // MARK: Properties
    
    public weak var delegate: DeviceDelegate? = nil
    
    public let id: Id
    public let name: String
    public let type: DeviceType
    public let incomingCapabilities: Set<Service.Capability>
    public let outgoingCapabilities: Set<Service.Capability>
    public let config: DeviceConfiguration
    
    public private(set) var state: State = .unavailable {
        didSet {
            if oldValue != self.state {
                self.delegate?.device(self, didChangeState: self.state)
            }
        }
    }
    
    private var connections: [Connection] = []
    private var packetHandlers: [DeviceDataPacketHandler] = []
    
    
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
        if let index = self.connections.index(where: { return (type(of: $0) == type(of: connection)) && ($0 !== connection) }) {
            self.connections[index].close()
        }
        
        self.updateState()
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
        return self.delegate?.serviceActions(for: self) ?? []
    }
    
    /// Send a data packet to remote device. A most appropriate connection for the task
    /// would be chosen automatically. Completion block may be provided - it would be called
    /// when packet is successfully sent. On failure completion handler would not be called -
    /// whole connection would be closed instead
    public func send(_ packet: DataPacket, whenCompleted: Connection.SendingCompletionHandler? = nil) {
        if let connection = self.connectionForSending() {
            connection.send(packet, whenCompleted: whenCompleted)
        }
    }
    
    
    // MARK: ConnectionDelegate
    
    public func connection(_ connection: Connection, didSwitchToState state: Connection.State) {
        Log.debug?.message("connection(<\(connection)> didSwitchToState:<\(state)>)")
        switch state {
        case .Closed:
            if let index = self.connections.index(of: connection) {
                self.connections.remove(at: index)
                self.updateState()
            }
            else {
                Log.error?.message("Connection not found in device connections list")
            }
        default:
            Log.error?.message("Unexpected connection state switch: \(connection) -> \(state)")
        }
    }
    
    public func connection(_ connection: Connection, didSendPacket packet: DataPacket, uploadedPayload: Bool) {
        
    }
    
    public func connection(_ connection: Connection, didReadPacket packet: DataPacket) {
        self.handle(packet: packet, onConnection: connection)
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
    
    public var pairingDelegate: PairableDelegate? = nil
    
    public var pairingStatus: PairingStatus
    
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
            switch connection.pairingStatus{
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
    }
    
    public func updatePairingStatus(globalStatus: PairingStatus) {
        for connection in self.connections {
            connection.updatePairingStatus(globalStatus: globalStatus)
        }
        self.pairingStatus = globalStatus
        self.config.isPaired = globalStatus == .Paired
        
        self.updateState()
    }
    
    
    // MARK: Private
    
    private func updateState() {
        if self.connections.count == 0 {
            self.state = .unavailable
        }
        else if self.pairingStatus == .Paired {
            self.state = .paired
        }
        else if self.pairingStatus == .Requested || self.pairingStatus == .RequestedByPeer {
            self.state = .pairing
        }
        else {
            self.state = .unpaired
        }
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
}
