//
//  DeviceManager.swift
//  Soduto
//
//  Created by Admin on 2016-08-13.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import CleanroomLogger

public protocol DeviceManagerDelegate: class {
    func deviceManager(_ manager: DeviceManager, didChangeDeviceState device: Device)
    func deviceManager(_ manager: DeviceManager, didReceivePairingRequest request: PairingRequest, forDevice device: Device)
}

public protocol DeviceDataSource: class {
    var unpairedDevices: [Device] { get }
    var pairedDevices: [Device] { get }
    var unavailableDevices: [Device] { get }
}

public protocol DeviceManagerConfiguration {
    func deviceConfig(for deviceId:Device.Id) -> DeviceConfiguration
    func knownDeviceConfigs() -> [DeviceConfiguration]
    var hostDeviceId: Device.Id { get }
}

public class DeviceManager: ConnectionProviderDelegate, DeviceDelegate, DeviceDataSource {
    
    // MARK: Properties
    
    public weak var delegate: DeviceManagerDelegate? = nil
    
    public var unpairedDevices: [Device] {
        let filtered = self.devices.filter { $0.value.state == Device.State.unpaired || $0.value.state == Device.State.pairing }
        return filtered.map { $0.value }
    }
    
    public var pairedDevices: [Device] {
        let filtered = self.devices.filter { $0.value.state == Device.State.paired }
        return filtered.map { $0.value }
    }
    
    public var unavailableDevices: [Device] {
        let configs = config.knownDeviceConfigs().filter { self.devices[$0.deviceId] == nil && $0.isPaired }
        return configs.map { Device(config: $0) }
    }
    
    private let config: DeviceManagerConfiguration
    private let serviceManager: ServiceManager
    private var devices: [Device.Id:Device] = [:]
    
    
    // MARK: Init / Deinit
    
    init(config: DeviceManagerConfiguration, serviceManager: ServiceManager) {
        self.config = config
        self.serviceManager = serviceManager
    }
    
    
    // MARK: ConnectionProviderDelegate
    
    public func isNewConnectionNeeded(byProvider provider: ConnectionProvider, deviceId: Device.Id) -> Bool {
        if deviceId == self.config.hostDeviceId { return false }
        if devices[deviceId] != nil { return false }
        return true
    }
    
    public func connectionProvider(_ provider: ConnectionProvider, didCreateConnection connection: Connection) {
        Log.debug?.message("connectionProvider(<\(provider)> didCreateConnection:<\(connection)>)")
        
        assert(connection.state == .Open, "Connection from connection provider expected to be in open state")
        assert(connection.identity != nil, "Connection identity expected to be not nil")
        
        do {
            let deviceId = try connection.identity!.getDeviceId() as Device.Id
            if let device = self.devices[deviceId] {
                device.addConnection(connection)
            }
            else {
                try self.addNewDevice(withId: deviceId, connection: connection)
            }
        }
        catch {
            Log.error?.message("Error adding new connection: \(error)")
        }
    }
    
    
    // MARK: Public methods
    
    public func device(withId id: Device.Id) -> Device? {
        return self.devices[id]
    }
    
    
    // MARK: DeviceDelegate
    
    public func device(_ device: Device, didChangeState state: Device.State) {
        Log.debug?.message("device(<\(device)> didChangeState:<\(state)>)")
        
        if state == .paired {
            self.serviceManager.setup(for: device)
        }
        else {
            // This needs to be done only when old state was paired. However we dont know previous state here
            // Assuming cleanup is not that heavyweight that it should be done very cautiously
            self.serviceManager.cleanup(for: device)
        }
        
        if state == .unavailable {
            self.devices.removeValue(forKey: device.id)
        }
        
        self.delegate?.deviceManager(self, didChangeDeviceState: device)
    }
    
    public func device(_ device: Device, didReceivePairingRequest request: PairingRequest) {
        self.delegate?.deviceManager(self, didReceivePairingRequest: request, forDevice: device)
    }
    
    public func serviceActions(for device: Device) -> [ServiceAction] {
        let services = self.serviceManager.services(supportingOutgoingCapabilities: device.incomingCapabilities)
        let actions = services.flatMap {
            return $0.actions(for: device)
        }
        return actions
    }
    
    
    // MARK: Private methods
    
    private func addNewDevice(withId id: Device.Id, connection: Connection) throws {
        let device = try Device(connection: connection, config: self.config.deviceConfig(for: id))
        device.delegate = self
        
        let services: [DeviceDataPacketHandler] = self.serviceManager.services(supportingIncomingCapabilities: device.outgoingCapabilities)
        device.addDataPacketHandlers(services)
        
        self.devices[device.id] = device
        self.device(device, didChangeState: device.state)
    }
}
