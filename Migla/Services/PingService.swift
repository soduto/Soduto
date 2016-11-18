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
    
    public var isPingPacket: Bool { return self.type == DataPacket.PingPacketType }
    
}

public class PingService: Service {
    
    public let incomingCapabilities = Set<Service.Capability>([ "kdeconnect.ping" ])
    public let outgoingCapabilities = Set<Service.Capability>([ "kdeconnect.ping" ])
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        
        guard dataPacket.isPingPacket else { return false }
        
        Swift.print("Ping packet received from device '\(device.name)': \(dataPacket)")
        
        return true
    }
    
}
