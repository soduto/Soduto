//
//  CapabilitiesManager.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-11-17.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public class ServiceManager: CapabilitiesDataSource {
    
    // MARK: Public properties
    
    /// Combined incoming capabilities of all services
    public var incomingCapabilities: Set<Service.Capability> {
        let capabilities = self.services.flatMap {
            return $0.incomingCapabilities
        }
        return Set(capabilities)
    }
    
    /// Combined outgoing capabilities of all services
    public var outgoingCapabilities: Set<Service.Capability> {
        let capabilities = self.services.flatMap {
            return $0.outgoingCapabilities
        }
        return Set(capabilities)
    }
    
    /// All registered service instances
    public private(set) var services: [Service] = []
    
    
    // MARK: Public methods
    
    /// Return services filtered by incoming capabilities
    public func services(supportingIncomingCapabilities capabilities: Set<Service.Capability>) -> [Service] {
        return self.services.filter {
            return !$0.incomingCapabilities.isDisjoint(with: capabilities)
        }
    }
    
    public func add(service: Service) {
        services.append(service)
    }
    
}
