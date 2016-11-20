//
//  ServiceAction.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-11-19.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

/// `ServiceAction` abstracts server supported actions in a manner suitable for different uses,
/// be it a GUI, command line or some other use. For example GUI does not need to know 
/// particular methods supported by various servers - it can ask the Core to provide actions 
/// for particular device and create a menu item for each of the actions returned. 
/// `ServiceAction` encapsulates all the information needed to perform an action, so no
/// additional parameters needed to be supplied
public struct ServiceAction {
    
    // MARK: Types
    
    public typealias Id = Int
    
    
    // MARK: Public properties
    
    /// Action id uniquely defining concrete action to be performed on particular service.
    /// Same ids on different services may mean different actions, so only a pair of 
    /// id and service uniquely define an action.
    public let id: Id
    
    /// Short action title suitable to display in UI
    public let title: String
    
    /// Possibly slightly longer than title action description suitable to display in UI
    public let decription: String
    
    public let service: Service
    public let device: Device
    
    
    // MARK: Init / Deinit
    
    init(id: Id, title: String, description: String, service: Service, device: Device) {
        self.id = id
        self.title = title
        self.decription = description
        self.service = service
        self.device = device
    }
    
    
    // MARK: Public methods
    
    public func perform() {
        service.performAction(self.id, forDevice: self.device)
    }
}
