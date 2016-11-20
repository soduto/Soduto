//
//  PingService.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-11-18.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

/// Ping service data packet utilities
public extension DataPacket {
    
    public static let PingPacketType = "kdeconnect.ping"
    
    enum PingProperty: String {
        case message = "message"
    }
    
    public static func pingPacket() -> DataPacket {
        return DataPacket(type: PingPacketType, body: [
            PingProperty.message.rawValue: "Testing connection." as AnyObject
        ])
    }
    
    public var isPingPacket: Bool { return self.type == DataPacket.PingPacketType }
}

public class PingService: Service {
    
    // MARK: Types
    
    enum ActionId: ServiceAction.Id {
        case send
    }
    
    
    // MARK: Constants
    
    public static let pingCapability: Service.Capability = "kdeconnect.ping"
    
    
    // MARK: Service properties
    
    public let incomingCapabilities = Set<Service.Capability>([ PingService.pingCapability ])
    public let outgoingCapabilities = Set<Service.Capability>([ PingService.pingCapability ])
    
    
    // MARK: Service methods
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        
        guard dataPacket.isPingPacket else { return false }
        
        Swift.print("Ping packet received from device '\(device.name)': \(dataPacket)")
        
        return true
    }
    
    public func actions(for device: Device) -> [ServiceAction] {
        guard device.incomingCapabilities.contains(PingService.pingCapability) else { return [] }
        
        return [
            ServiceAction(id: ActionId.send.rawValue, title: "Test connection", description: "Send ping to the remote device to test connectivity", service: self, device: device)
        ]
    }
    
    public func performAction(_ id: ServiceAction.Id, forDevice device: Device) {
        guard let actionId = ActionId(rawValue: id) else { return }
        
        switch actionId {
        case .send:
            device.send(DataPacket.pingPacket())
            break
        }
        
    }
}
