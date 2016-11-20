//
//  FindMyPhoneService.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-11-20.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

/// Find my phone service data packet utilities
public extension DataPacket {
    
    public static let findMyPhoneRequestPacketType = "kdeconnect.findmyphone.request"
    
    public static func findMyPhonePacket() -> DataPacket {
        return DataPacket(type: findMyPhoneRequestPacketType, body: Body())
    }
}

/// Send request to ring the phone even if it is silenced
public class FindMyPhoneService: Service {
    
    // MARK: Types
    
    enum ActionId: ServiceAction.Id {
        case findMyPhone
    }
    
    
    // MARK: Service properties
    
    public let incomingCapabilities = Set<Service.Capability>()
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.findMyPhoneRequestPacketType ])
    
    
    // MARK: Service methods
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        return false
    }
    
    public func actions(for device: Device) -> [ServiceAction] {
        guard device.incomingCapabilities.contains(DataPacket.findMyPhoneRequestPacketType) else { return [] }
        
        return [
            ServiceAction(id: ActionId.findMyPhone.rawValue, title: "Find my phone", description: "Ring the phone even if it is silenced", service: self, device: device)
        ]
    }
    
    public func performAction(_ id: ServiceAction.Id, forDevice device: Device) {
        guard let actionId = ActionId(rawValue: id) else { return }
        
        switch actionId {
        case .findMyPhone:
            device.send(DataPacket.findMyPhonePacket())
            break
        }
        
    }
}
