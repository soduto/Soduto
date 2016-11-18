//
//  DeviceManager.swift
//  Migla
//
//  Created by Admin on 2016-08-13.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public protocol DeviceManagerDelegate: class {
    func deviceManager(_ manager: DeviceManager, didChangeDeviceState device: Device)
    func deviceManager(_ manager: DeviceManager, didReceivePairingRequest request: PairingRequest, forDevice device: Device)
}

public protocol DeviceDataSource: class {
    var unpairedDevices: [Device] { get }
    var pairedDevices: [Device] { get }
}

public protocol DeviceManagerConfiguration {
    func deviceConfig(for deviceId:Device.Id) -> DeviceConfiguration
    var hostDeviceId: Device.Id { get }
}

public class DeviceManager: ConnectionProviderDelegate, DeviceDelegate, DeviceDataSource {
    
    public weak var delegate: DeviceManagerDelegate? = nil
    
    public var unpairedDevices: [Device] {
        let filtered = self.devices.filter { $0.value.state == Device.State.unpaired || $0.value.state == Device.State.pairing }
        return filtered.map { $0.value }
    }
    
    public var pairedDevices: [Device] {
        let filtered = self.devices.filter { $0.value.state == Device.State.paired }
        return filtered.map { $0.value }
    }
    
    private let config: DeviceManagerConfiguration
    private var devices: [Device.Id:Device] = [:]
    
    
    init(config: DeviceManagerConfiguration) {
        self.config = config
    }
    
    
    // MARK: ConnectionProviderDelegate
    
    public func isNewConnectionNeeded(byProvider provider: ConnectionProvider, deviceId: Device.Id) -> Bool {
        if deviceId == self.config.hostDeviceId { return false }
        if devices[deviceId] != nil { return false }
        return true
    }
    
    public func connectionProvider(_ provider: ConnectionProvider, didCreateConnection connection: Connection) {
        Swift.print("DeviceManager.connectionProvider:didCreateConnection: \(provider) \(connection)")
        
        assert(connection.state == .Open, "Connection from connection provider expected to be in open state")
        assert(connection.identity != nil, "Connection identity expected to be not nil")
        
        do {
            let deviceId = try connection.identity!.getDeviceId() as Device.Id
            if let device = self.devices[deviceId] {
                device.addConnection(connection)
            }
            else {
                let device = try Device(connection: connection, config: self.config.deviceConfig(for: deviceId))
                device.delegate = self
                self.devices[device.id] = device
                self.delegate?.deviceManager(self, didChangeDeviceState: device)
            }
        }
        catch {
            Swift.print("Error adding new connection: \(error)")
        }
    }
    
    
    // MARK: DeviceDelegate
    
    public func device(_ device: Device, didChangeState state: Device.State) {
        Swift.print("DeviceManager.device:didChangeState: \(device) \(state)")
        
        if state == .unavailable {
            self.devices.removeValue(forKey: device.id)
        }
        
        self.delegate?.deviceManager(self, didChangeDeviceState: device)
    }
    
    public func device(_ device: Device, didReceivePairingRequest request: PairingRequest) {
        self.delegate?.deviceManager(self, didReceivePairingRequest: request, forDevice: device)
    }
    
}
