//
//  Capability.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-11-18.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public protocol Service: class, DeviceDataPacketHandler {
    
    typealias Capability = String
    
    var incomingCapabilities: Set<Capability> { get }
    var outgoingCapabilities: Set<Capability> { get }
    
    
}
