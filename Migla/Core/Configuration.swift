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
    
    private let userDefaults: UserDefaults
    
    
    
    init(deviceId: Device.Id, userDefaults: UserDefaults) {
        self.deviceId = deviceId
        self.isPaired = false
        self.userDefaults = userDefaults
        
        let key = type(of: self).configKey(forDevice: deviceId)
        if let attrs = self.userDefaults.dictionary(forKey: key) {
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
        self.userDefaults.set(attrs, forKey: key)
    }
}



public protocol HostConfiguration {
    var hostDeviceName: String { get }
    var hostDeviceType: DeviceType { get }
    var hostDeviceId: Device.Id { get }
}

public class Configuration: ConnectionConfiguration, DeviceManagerConfiguration, HostConfiguration {
    
    enum Property: String {
        case hostName = "hostName"
        case hostDeviceId = "hostDeviceId"
    }
    
    
   
    convenience init() {
        self.init(userDefaults: UserDefaults.standard)
    }
    
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        
        if self.userDefaults.string(forKey: Property.hostDeviceId.rawValue) == nil {
            // generate and store device ID for current device
            self.userDefaults.set(Configuration.generateDeviceId(), forKey: Property.hostDeviceId.rawValue)
        }
    }
    
    
    
    private let userDefaults: UserDefaults
    
    
    
    public var hostDeviceName: String {
        return Host.current().localizedName ?? "Migla"
    }
    
    public var hostDeviceType: DeviceType {
        return .Desktop
    }
    
    public var hostDeviceId: Device.Id {
        get { return self.userDefaults.string(forKey: Property.hostDeviceId.rawValue)! }
    }
    
    public func deviceConfig(for deviceId: Device.Id) -> DeviceConfiguration {
        return DeviceConfiguration(deviceId: deviceId, userDefaults: self.userDefaults)
    }
    
    
    
    class func generateDeviceId() -> Device.Id {
        let uuid = UUID().uuidString
        let deviceId = String(uuid.characters.map { return isSafeDeviceIdCharacter($0) ? $0 : "_" })
        return deviceId
    }
    
    class func isSafeDeviceIdCharacter(_ c: Character) -> Bool {
        return (c >= "0" && c <= "9") || (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c == "_")
    }
}
