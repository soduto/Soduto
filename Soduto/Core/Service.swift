//
//  Capability.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-11-18.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation

public protocol Service: class, DeviceDataPacketHandler {
    
    typealias Capability = String
    typealias Id = String
    
    static var serviceId: Id { get }
    
    var incomingCapabilities: Set<Capability> { get }
    var outgoingCapabilities: Set<Capability> { get }
    
    func setup(for device: Device)
    func cleanup(for device: Device)
    
    func actions(for device: Device) -> [ServiceAction]
    func performAction(_ id: ServiceAction.Id, forDevice device: Device)
}

extension Service {
    var id: Id { return type(of: self).serviceId }
}
