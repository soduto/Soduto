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
    
    /// Return services filtered by outgoing capabilities
    public func services(supportingOutgoingCapabilities capabilities: Set<Service.Capability>) -> [Service] {
        return self.services.filter {
            return !$0.outgoingCapabilities.isDisjoint(with: capabilities)
        }
    }
    
    /// Add a new service instance. This should be done on application start before any device connections are established
    public func add(service: Service) {
        services.append(service)
    }
    
    /// Setup services for provided device. This is done when a new device becomes ready (accessible and paired)
    public func setup(for device: Device) {
        for service in self.services {
            service.setup(for: device)
        }
    }
    
    /// Clenup services for provided device. This is done when device becomes unavailable or not unpaired
    public func cleanup(for device: Device) {
        for service in self.services {
            service.cleanup(for: device)
        }
    }
}
