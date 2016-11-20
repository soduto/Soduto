//
//  DeviceMenu.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-11-20.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import Cocoa

public class DeviceMenu: NSMenu {
    
    // MARK: Public properties
    
    public let device: Device
    
    
    // MARK: Init / Deinit
    
    public init(device: Device) {
        self.device = device
        
        super.init(title: device.name)
        
        self.autoenablesItems = false
        
        let actions = device.serviceActions()
        for action in actions {
            let item = ServiceActionMenuItem(serviceAction: action)
            self.addItem(item)
        }
    }
    
    required public init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
