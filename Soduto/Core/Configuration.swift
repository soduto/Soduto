//
//  Configuration.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-10-09.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import CleanroomLogger
import ServiceManagement

public class DeviceConfiguration: NSObject {
    
    // MARK: Types
    
    public enum Property: String {
        case name = "name"
        case type = "type"
        case isPaired = "isPaired"
        case certificateName = "certificateName"
        case hwAddresses = "hwAddresses"
    }
    
    
    // MARK: Properties
    
    public let deviceId: Device.Id
    
    public var name: String {
        didSet {
            if self.name != oldValue {
                self.save()
            }
        }
    }
    
    public var type: DeviceType {
        didSet {
            if self.type != oldValue {
                self.save()
            }
        }
    }
    
    public var isPaired: Bool {
        didSet {
            if self.isPaired != oldValue {
                self.save()
            }
        }
    }
    
    public private(set) var certificateName: String {
        didSet {
            if self.certificateName != oldValue {
                self.save()
            }
        }
    }
    
    public var certificate: SecCertificate? {
        get {
            guard !self.certificateName.isEmpty else { return nil }
            
            return CertificateUtils.findCertificate(self.certificateName)
        }
        set {
            do {
                if self.certificateName.isEmpty && newValue != nil {
                    self.certificateName = DeviceConfiguration.defaultCertificateName(for: deviceId)
                }
                if !self.certificateName.isEmpty {
                    try CertificateUtils.deleteCertificate(self.certificateName)
                }
                if let newValue = newValue {
                    try CertificateUtils.addCertificate(newValue, name: self.certificateName)
                }
            }
            catch {
                Log.error?.message("Failed to update certificate: \(error)")
            }
        }
    }
    
    public var hwAddresses: [String] {
        didSet {
            if self.hwAddresses != oldValue {
                self.save()
            }
        }
    }
    
    
    private static let configKeyPrefix = "com/soduto/device/"
    private let userDefaults: UserDefaults
    private var isLoading: Bool = false
    
    
    // MARK: Init / Deinit
    
    init(deviceId: Device.Id, userDefaults: UserDefaults) {
        self.deviceId = deviceId
        self.userDefaults = userDefaults
        self.name = ""
        self.type = .Unknown
        self.isPaired = false
        self.certificateName = ""
        self.hwAddresses = []
        
        super.init()
        
        self.load()
        self.startObserving()
    }
    
    convenience init(configKey: String, userDefaults: UserDefaults) {
        assert(DeviceConfiguration.isDeviceConfigKey(configKey), "configKey is not a valid device configuration key")
    
        let deviceId: Device.Id
        if DeviceConfiguration.isDeviceConfigKey(configKey) {
            deviceId = configKey.substring(from: configKey.index(configKey.startIndex, offsetBy: DeviceConfiguration.configKeyPrefix.characters.count))
        }
        else {
            deviceId = ""
        }
        
        self.init(deviceId: deviceId, userDefaults: userDefaults)
    }
    
    deinit {
        self.stopObserving()
    }
    
    
    // MARK: NSObject
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        let key = DeviceConfiguration.configKey(for: deviceId)
        if keyPath == key {
            self.load()
        }
        else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    
    // MARK: Public functions
    
    public class func isDeviceConfigKey(_ key: String) -> Bool {
        return key.hasPrefix(configKeyPrefix)
    }
    
    public func addHwAddress(_ address: String) {
        if !self.hwAddresses.contains(address) {
            self.hwAddresses.append(address)
            self.save()
        }
    }
    
    
    // MARK: Private
    
    class func defaultCertificateName(for deviceId: String) -> String {
        let safeDeviceId = deviceId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "undefined-\(Configuration.generateDeviceId())"
        return "Soduto Client (\(safeDeviceId))"
    }
    
    class func configKey(for deviceId: String) -> String {
        let safeDeviceId: String = deviceId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "undefined-\(Configuration.generateDeviceId())"
        return "\(configKeyPrefix)\(safeDeviceId)"
    }
    
    func load() {
        assert(!self.isLoading, "Loading should not be recursive")
        guard !self.isLoading else { return }
        
        isLoading = true
        
        let key = DeviceConfiguration.configKey(for: deviceId)
        if let attrs = self.userDefaults.dictionary(forKey: key) {
            self.name = attrs[Property.name.rawValue] as? String ?? self.name
            self.type = DeviceType(rawValue: attrs[Property.type.rawValue] as? String ?? "") ?? self.type
            self.isPaired = attrs[Property.isPaired.rawValue] as? Bool ?? self.isPaired
            self.certificateName = attrs[Property.certificateName.rawValue] as? String ?? self.certificateName
            self.hwAddresses = attrs[Property.hwAddresses.rawValue] as? [String] ?? self.hwAddresses
        }
        
        isLoading = false
    }
    
    func save() {
        guard !self.isLoading else { return }
        guard self.deviceId != "" else { return }
        
        let key = DeviceConfiguration.configKey(for: self.deviceId)
        let attrs:[String:AnyObject] = [
            Property.name.rawValue: self.name as AnyObject,
            Property.type.rawValue: self.type.rawValue as AnyObject,
            Property.isPaired.rawValue: self.isPaired as AnyObject,
            Property.certificateName.rawValue: self.certificateName as AnyObject,
            Property.hwAddresses.rawValue: self.hwAddresses as AnyObject
        ]
        self.userDefaults.set(attrs, forKey: key)
    }
    
    func startObserving() {
        let key = DeviceConfiguration.configKey(for: deviceId)
        self.userDefaults.addObserver(self, forKeyPath: key, options: .old, context: nil)
    }
    
    func stopObserving() {
        let key = DeviceConfiguration.configKey(for: deviceId)
        self.userDefaults.removeObserver(self, forKeyPath: key)
    }
}


public protocol CapabilitiesDataSource: class {
    var incomingCapabilities: Set<Service.Capability> { get }
    var outgoingCapabilities: Set<Service.Capability> { get }
}

public protocol HostConfiguration {
    var hostDeviceName: String { get }
    var hostDeviceType: DeviceType { get }
    var hostDeviceId: Device.Id { get }
    var incomingCapabilities: Set<Service.Capability> { get }
    var outgoingCapabilities: Set<Service.Capability> { get }
}

public class Configuration: ConnectionConfiguration, DeviceManagerConfiguration, HostConfiguration {
    
    enum Property: String {
        case hostName = "hostName"
        case hostDeviceId = "hostDeviceId"
        case hostCertificateName = "hostCertificateName"
        case launchOnLogin = "launchOnLogin"
    }
    
    
    
    public weak var capabilitiesDataSource: CapabilitiesDataSource? = nil
    
    private let userDefaults: UserDefaults
    
    
   
    convenience init() {
        self.init(userDefaults: UserDefaults.standard)
    }
    
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        
        if self.userDefaults.string(forKey: Property.hostDeviceId.rawValue) == nil {
            self.userDefaults.set(Configuration.generateDeviceId(), forKey: Property.hostDeviceId.rawValue)
        }
        if self.userDefaults.string(forKey: Property.hostCertificateName.rawValue) == nil {
            self.userDefaults.set("Soduto Host", forKey: Property.hostCertificateName.rawValue)
        }
    }
    
    
    
    public var hostDeviceName: String {
        return Host.current().localizedName ?? "Soduto"
    }
    
    public var hostDeviceType: DeviceType {
        return .Desktop
    }
    
    public var hostDeviceId: Device.Id {
        return self.userDefaults.string(forKey: Property.hostDeviceId.rawValue)!
    }
    
    public var hostCertificate: SecIdentity? {
        guard let name = self.userDefaults.string(forKey: Property.hostCertificateName.rawValue) else {
            Log.error?.message("Failed to get host certificate name")
            return nil
        }
        let expirationInterval = 60.0 * 60.0 * 24.0 * 365.0 * 10.0
        do {
            return try CertificateUtils.getOrCreateIdentity(name, certCommonName: hostDeviceId, expirationInterval: expirationInterval)
        }
        catch {
            Log.error?.message("Failed to get host identity for SSL: \(error)")
            return nil
        }
    }
    
    public func deviceConfig(for deviceId: Device.Id) -> DeviceConfiguration {
        return DeviceConfiguration(deviceId: deviceId, userDefaults: self.userDefaults)
    }
    
    public func knownDeviceConfigs() -> [DeviceConfiguration] {
        var configs: [DeviceConfiguration] = []
        
        let allSettings = self.userDefaults.dictionaryRepresentation()
        let keys = allSettings.keys
        for key in keys {
            guard DeviceConfiguration.isDeviceConfigKey(key) else { continue }
            configs.append(DeviceConfiguration(configKey: key, userDefaults: self.userDefaults))
        }
        
        return configs
    }
    
    public var incomingCapabilities: Set<Service.Capability> {
        return self.capabilitiesDataSource?.incomingCapabilities ?? Set()
    }
    
    public var outgoingCapabilities: Set<Service.Capability> {
        return self.capabilitiesDataSource?.outgoingCapabilities ?? Set()
    }
    
    public var launchOnLogin: Bool {
        get { return self.userDefaults.bool(forKey: Property.launchOnLogin.rawValue) }
        set {
            if SMLoginItemSetEnabled("com.soduto.SodutoLauncher" as CFString, newValue) {
                self.userDefaults.set(newValue, forKey: Property.launchOnLogin.rawValue)
            }
        }
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
