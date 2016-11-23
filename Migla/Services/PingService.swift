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
    
    public static let pingPacketType = "kdeconnect.ping"
    
    enum PingError: Error {
        case wrongType
        case invalidMessage
    }
    
    enum PingProperty: String {
        case message = "message"
    }
    
    public static func pingPacket() -> DataPacket {
        return DataPacket(type: pingPacketType, body: [
            PingProperty.message.rawValue: "Testing connection." as AnyObject
        ])
    }
    
    public func getMessage() throws -> String? {
        try self.validatePingType()
        guard body.keys.contains(PingProperty.message.rawValue) else { return nil }
        guard let message = body[PingProperty.message.rawValue] as? String else { throw PingError.invalidMessage }
        return message
    }
    
    public var isPingPacket: Bool { return self.type == DataPacket.pingPacketType }
    
    public func validatePingType() throws {
        guard self.isPingPacket else { throw PingError.wrongType }
    }
}

/// Service providing capability to send end receive "pings" - short messages that can be used to test 
/// devices connectivity
public class PingService: Service {
    
    // MARK: Types
    
    enum ActionId: ServiceAction.Id {
        case send
    }
    
    
    // MARK: Service properties
    
    public let incomingCapabilities = Set<Service.Capability>([ DataPacket.pingPacketType ])
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.pingPacketType ])
    
    
    // MARK: Service methods
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        
        guard dataPacket.isPingPacket else { return false }
        
        self.showNotification(for: dataPacket, from: device)
        
        return true
    }
    
    public func actions(for device: Device) -> [ServiceAction] {
        guard device.incomingCapabilities.contains(DataPacket.pingPacketType) else { return [] }
        
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
    
    
    // MARK: Private methods
    
    private func showNotification(for dataPacket: DataPacket, from device: Device) {
        assert(dataPacket.isPingPacket, "Expected ping data packet")
        
        let notification = NSUserNotification()
        notification.title = device.name
        notification.informativeText = try? dataPacket.getMessage() ?? "Ping!"
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.hasActionButton = false
        notification.identifier = "com.migla.pingservice.ping.device.\(device.id)"
        NSUserNotificationCenter.default.scheduleNotification(notification)
        
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            NSUserNotificationCenter.default.removeDeliveredNotification(notification)
        }
    }
}
