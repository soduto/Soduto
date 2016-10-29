//
//  Configuration.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-10-09.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public class DeviceConfiguration {
    
    public enum Property: String {
        case isPaired = "isPaired"
    }
    
    
    
    public let deviceId: Device.Id
    public var isPaired: Bool {
        didSet {
            if self.isPaired != oldValue {
                self.save()
            }
        }
    }
    
    
    
    init(deviceId: Device.Id) {
        self.deviceId = deviceId
        self.isPaired = false
        
        let key = type(of: self).configKey(forDevice: deviceId)
        if let attrs = UserDefaults.standard.dictionary(forKey: key) {
            self.isPaired = attrs[Property.isPaired.rawValue] as? Bool ?? false
        }
    }
    
    
    
    class func configKey(forDevice deviceId: Device.Id) -> String {
        let safeDeviceId = deviceId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        return "com.migla.device.\(safeDeviceId)"
    }
    
    func save() {
        let key = type(of: self).configKey(forDevice: deviceId)
        let attrs:[String:AnyObject] = [
            Property.isPaired.rawValue: self.isPaired as AnyObject
        ]
        UserDefaults.standard.set(attrs, forKey: key)
    }
}

public class Configuration: ConnectionConfiguration, DeviceManagerConfiguration {
   
    public func deviceConfig(for deviceId: Device.Id) -> DeviceConfiguration {
        return DeviceConfiguration(deviceId: deviceId)
    }

}
