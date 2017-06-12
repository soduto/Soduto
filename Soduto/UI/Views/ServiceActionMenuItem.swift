//
//  ServiceActionMenuItem.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-11-20.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import Cocoa

public class ServiceActionMenuItem: NSMenuItem {
    
    // MARK: Public properties
    
    public let serviceAction: ServiceAction
    
    
    // MARK: Init / Deinit
    
    public init(serviceAction: ServiceAction) {
        self.serviceAction = serviceAction
        
        super.init(title: serviceAction.title, action: #selector(performServiceAction), keyEquivalent: "")
        
        self.target = self
    }
    
    required public init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // MARK: Public methods
    
    @objc public func performServiceAction() {
        serviceAction.perform()
    }
}
