//
//  ServiceConfiguration.swift
//  Soduto
//
//  Created by Giedrius on 2017-07-21.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation

public class ServiceConfiguartion {
    
    // MARK: Properties
    
    public let serviceId: Service.Id
    private let userDefaults: UserDefaults
    private let configKeyPrefix: String
    
    
    // MARK: Init / Deinit
    
    init(serviceId: Service.Id, userDefaults: UserDefaults) {
        self.serviceId = serviceId
        self.userDefaults = userDefaults
        self.configKeyPrefix = (serviceId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)?.replacingOccurrences(of: ".", with: "/") ?? "com/soduto/service/undefined") + "/"
    }
    
    
    // MARK: Generic Value Access
    
    public func boolValue(forKey key: String, deviceId: Device.Id?, fallback: Bool = false) -> Bool {
        return value(forKey: key, deviceId: deviceId) as? Bool ?? fallback
    }
    
    public func set(_ value: Bool?, forKey key: String, deviceId: Device.Id?) {
        setValue(value, forKey: key, deviceId: deviceId)
    }
    
    public func isValueOverridden(forKey key: String, deviceId: Device.Id) -> Bool {
        return configDictionary(forDevice: deviceId)[key] != nil
    }
    
    
    // MARK: Private
    
    private func configKey(forDevice deviceId: Device.Id?) -> String {
        let devicePart: String = deviceId?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "default"
        return self.configKeyPrefix + devicePart
    }

    private func configDictionary(forDevice deviceId: Device.Id?) -> [String:Any] {
        let key = configKey(forDevice: deviceId)
        return self.userDefaults.dictionary(forKey: key) ?? [:]
    }
    
    private func setConfigurationDictionary(_ dict: [String:Any], forDevice deviceId: Device.Id?) {
        let key = configKey(forDevice: deviceId)
        self.userDefaults.set(dict, forKey: key)
    }
    
    private func value(forKey key: String, deviceId: Device.Id?) -> Any? {
        if let deviceId = deviceId, let value = configDictionary(forDevice: deviceId)[key] {
            return value
        }
        return configDictionary(forDevice: nil)[key]
    }
    
    private func setValue(_ value: Any?, forKey key: String, deviceId: Device.Id?) {
        var dict = configDictionary(forDevice: deviceId)
        if let value = value {
            dict[key] = value
        }
        else {
            dict.removeValue(forKey: key)
        }
        setConfigurationDictionary(dict, forDevice: deviceId)
    }
    
}


// MARK: - Specialized Configuration Values

extension ServiceConfiguartion {
    
    // MARK: Types
    
    public struct Property {
        public static let isEnabled: String = "isEnabled"
    }
    
    
    // MARK: Accessors
    
    public func isEnabled(forDevice deviceId: Device.Id?) -> Bool {
        return boolValue(forKey: Property.isEnabled, deviceId: deviceId)
    }
    
    public func setEnabled(_ value: Bool?, forDevice deviceId: Device.Id?) {
        set(value, forKey: Property.isEnabled, deviceId: deviceId)
    }
    
    public func isEnabledOverridden(forDevice deviceId: Device.Id) -> Bool {
        return isValueOverridden(forKey: Property.isEnabled, deviceId: deviceId)
    }
    
}
