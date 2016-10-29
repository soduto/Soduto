//
//  Device.swift
//  Migla
//
//  Created by Admin on 2016-08-13.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation


/**
 
 Supported device types.
 
 - Unknown: Device type is not known. Usupported device types default to this.
 - Dektop: Device is desktop computer.
 - Laptop: Device is laptop computer.
 - Phone: Device is a mobile phone.
 - Tablet: Device is a tablet.
 
 */
public enum DeviceType: String {
    case Unknown = "unknown"
    case Desktop = "desktop"
    case Laptop = "laptop"
    case Phone = "phone"
    case Tablet = "tablet"
}


/**
 
 Errors thrown by Device instances.
 
 - InvalidConnection: provided connection has wrong state.
 
 */
public enum DeviceError: Error {
    case InvalidConnection
}


/**
 
 State of the Device instance.
 
 - Unavailable: Device is unreachable.
 - Unpaired: Device is reachable but not trusted (unpaired).
 - Paired: Device is reachable and trusted (paired).
 
 */
public enum DeviceState {
    case Unavailable
    case Unpaired
    case Pairing
    case Paired
}


/**
 
 Protocol for Device delegates.
 
 */
public protocol DeviceDelegate: class {
    func device(_ device: Device, didChangeState state: DeviceState)
    func device(_ device: Device, didReceivePairingRequest pairingRequest: PairingRequest)
}


/**
 
 Device class represents a remote device. Multiple connections to the device may be used, but only one of the same kind (LAN, Bluetooth, etc.)
 
 */
public class Device: ConnectionDelegate, PairableDelegate, Pairable {
    
    // MARK: Types
    
    public typealias Id = String
    
    
    // MARK: Properties
    
    public weak var delegate: DeviceDelegate? = nil
    
    public let id: Id
    public let name: String
    public let type: DeviceType
    public let config: DeviceConfiguration
    
    public private(set) var state: DeviceState = .Unavailable {
        didSet {
            if oldValue != self.state {
                self.delegate?.device(self, didChangeState: self.state)
            }
        }
    }
    
    private var connections: [Connection] = []
    
    
    // MARK: Initialization / Deinitialization
    
    /**
      Initialize Device with connection object. Device properties are initialized with connection identity property values.
     
      - Parameter connection: Fully initialized (i.e. in Open state) connection to the device.
      - Throws: `DeviceError.InvalidConnection` if connection state is not .Open or identity property is nil
                  `DataPacket.IdentityError` if connections identity property is invalid
     */
    public init(connection: Connection, config: DeviceConfiguration) throws {
        guard connection.state == .Open else { throw DeviceError.InvalidConnection }
        guard let identity = connection.identity else { throw DeviceError.InvalidConnection }
        
        self.id = try identity.getDeviceId()
        self.name = try identity.getDeviceName()
        self.type = DeviceType(rawValue: try identity.getDeviceType()) ?? DeviceType.Unknown
        self.config = config
        self.pairingStatus = self.config.isPaired ? .Paired : .Unpaired
        
        self.addConnection(connection)
    }
    
    
    // MARK Public API
    
    /**
      Add additional connection to the device. If the device has already contained a connection of the same kind, the old one is removed.
     
      - Parameter connection: Fully initialized (i.e. in Open state) connection to the device.
     */
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
    
    
    
    // MARK: ConnectionDelegate
    
    public func connection(_ connection: Connection, didSwitchToState state: Connection.State) {
        Swift.print("Device.connection:didSwitchToState: \(connection) \(state)")
        switch state {
        case .Closed:
            if let index = self.connections.index(of: connection) {
                self.connections.remove(at: index)
                self.updateState()
            }
            else {
                Swift.print("Connection not found in device connections list")
            }
        default:
            Swift.print("Unexpected connection state switch: \(connection) \(state)")
        }
    }
    
    public func connection(_ connection: Connection, didSendPacket packet: DataPacket) {
        
    }
    
    public func connection(_ connection: Connection, didReadPacket packet: DataPacket) {
        
    }
    
    
    // MARK: PairableDelegate
    
    public func pairable(_ pairable:Pairable, receivedRequest request:PairingRequest) {
        self.delegate?.device(self, didReceivePairingRequest: request)
    }
    
    public func pairable(_ pairable:Pairable, failedWithError error:Error) {
        Swift.print("Device.pairable:failedWithError: \(pairable) \(error)")
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
            self.state = .Unavailable
        }
        else if self.pairingStatus == .Paired {
            self.state = .Paired
        }
        else if self.pairingStatus == .Requested || self.pairingStatus == .RequestedByPeer {
            self.state = .Pairing
        }
        else {
            self.state = .Unpaired
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
}
