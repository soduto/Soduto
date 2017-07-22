//
//  BatteryService.swift
//  Soduto
//
//  Created by Giedrius on 2017-02-19.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa
import CleanroomLogger
import IOKit.ps

/// This service receives packages with type "kdeconnect.battery" and reads the
/// following fields:
///
/// - isCharging (boolean): If the battery of the peer device is charging
/// - currentCharge (int): The charge % of the peer device
/// - thresholdEvent (int) [optional when = 0, see below]:
/// means that a battery threshold event were fired on the remote device:
///     - 0: no event. generally not transmitted.
///     - 1: battery entered in low state
///
/// It also sends packages with type kdeconnect.battery and a field "request": true,
/// to ask the peer device to send a package like the mentioned above, and should
/// also answer this same kind of packages with its own information.
///
/// If the battery is low and discharging, it will notify the user.
public class BatteryService: Service {
    
    // MARK: Types
    
    public struct BatteryStatus {
        var currentCharge: Int
        var isCharging: Bool
        var isCritical: Bool { return !isCharging && currentCharge <= 2 }
    }
    
    public enum BatteryStatusError: Error {
        case readFailure(info: String)
    }
    
    
    // MARK: Properties
    
    public private(set) var statuses: [Device.Id:BatteryStatus] = [:]
    
    private var devices: [Device] = []
    private var runLoopSource: CFRunLoopSource?
    private var lastBatteryStatus: BatteryStatus?
    private let thresholdValue: Int = 15
    
    
    // MARK: Setup / Cleanup
    
    deinit {
        stopMonitoringBatteryState()
    }
    
    
    // MARK: Service
    
    public let id: Service.Id = "com.soduto.services.battery"
    
    public let incomingCapabilities = Set<Service.Capability>([ DataPacket.batteryPacketType, DataPacket.batteryRequestPacketType ])
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.batteryPacketType, DataPacket.batteryRequestPacketType ])
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        guard dataPacket.isBatteryPacket || dataPacket.isBatteryRequestPacket else { return false }
        
        do {
            if dataPacket.isBatteryRequestPacket{
                try handle(requestPacket: dataPacket, fromDevice: device)
            }
            else {
                try handle(statusPacket: dataPacket, fromDevice: device)
            }
        }
        catch {
            Log.error?.message("Error handling battery packet: \(error)")
        }
            
        return true
    }
    
    public func setup(for device: Device) {
        guard !self.devices.contains(where: { $0.id == device.id }) else { return }
        
        self.devices.append(device)
        
        device.send(DataPacket.batteryRequestPacket())
        
        if self.runLoopSource == nil {
            self.startMonitoringBatteryState()
        }
    }
    
    public func cleanup(for device: Device) {
        self.statuses.removeValue(forKey: device.id)
        
        guard let index = self.devices.index(where: { $0.id == device.id }) else { return }
        
        self.devices.remove(at: index)
        
        if self.devices.count == 0 {
            self.stopMonitoringBatteryState()
        }
    }
    
    public func actions(for device: Device) -> [ServiceAction] {
        // No supported actions
        return []
    }
    
    public func performAction(_ id: ServiceAction.Id, forDevice device: Device) {
        // No supported actions
    }
    
    
    // MARK: Private methods
    
    private func handle(requestPacket packet: DataPacket, fromDevice device: Device) throws {
        guard try packet.getRequestFlag() else { return }
        guard let status = getBatteryStatus() else { return }
        sendBatteryStatus(status, to: device)
    }
    
    private func handle(statusPacket packet: DataPacket, fromDevice device: Device) throws {
        let currentCharge = try packet.getCurrentCharge()
        let isCharging = try packet.getChargingFlag()
        let thresholdEvent = try packet.getThresholdEvent()
        let newStatus = BatteryStatus(currentCharge: currentCharge, isCharging: isCharging)
        self.statuses[device.id] = newStatus
        
        let notificationId = self.notificationId(for: device)
        let hasNotification = NSUserNotificationCenter.default.containsDeliveredNotification(withId: notificationId)
        if thresholdEvent == .batteryLow || hasNotification || newStatus.isCritical {
            self.showNotification(for: device, withStatus: newStatus)
        }
        else if isCharging {
            self.hideNotification(for: device)
        }
    }
    
    private func notificationId(for device: Device) -> NSUserNotification.Id {
        return "\(self.id).\(device.id)"
    }
    
    private func showNotification(for device: Device, withStatus status: BatteryStatus) {
        let title = NSLocalizedString("Low Battery", comment: "notification title")  + " | \(device.name)"
        let info = NSString(format: NSLocalizedString("%d%% of battery remaining", comment: "notification info") as NSString, status.currentCharge)

        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = info as String
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.hasActionButton = false
        notification.identifier = self.notificationId(for: device)
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    private func hideNotification(for device: Device) {
        let notificationId = self.notificationId(for: device)
        NSUserNotificationCenter.default.removeNotification(withId: notificationId)
    }
    
    private func getBatteryStatus() -> BatteryStatus? {
        do {
            // Take a snapshot of all the power source info
            guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
                else { throw BatteryStatusError.readFailure(info: "IOPSCopyPowerSourcesInfo failed") }
            
            // Pull out a list of power sources
            guard let sources: NSArray = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()
                else { throw BatteryStatusError.readFailure(info: "IOPSCopyPowerSourcesList failed") }
            
            // For each power source...
            for ps in sources {
                // Fetch the information for a given power source out of our snapshot
                guard let info: NSDictionary = IOPSGetPowerSourceDescription(snapshot, ps as CFTypeRef)?.takeUnretainedValue()
                    else { throw BatteryStatusError.readFailure(info: "IOPSGetPowerSourceDescription failed") }
                
                guard let capacity = info[kIOPSCurrentCapacityKey] as? Int else { continue }
                guard let maxCapacity = info[kIOPSMaxCapacityKey] as? Int else { continue }
                let isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
                
                let currentCharge = Int(Double(capacity) / Double(maxCapacity) * 100.0)
                return BatteryStatus(currentCharge: currentCharge, isCharging: isCharging)
            }
            
            return nil
            
        }
        catch {
            Log.error?.message("Failed to read battery status information: \(error)")
            return nil
        }
    }
    
    private func sendBatteryStatus(_ batteryStatus: BatteryStatus, to device: Device) {
        let chargeDropped = (self.lastBatteryStatus?.currentCharge ?? 100) > batteryStatus.currentCharge
        let chargeDropedBelowThreshold = chargeDropped && batteryStatus.currentCharge <= self.thresholdValue
        let thresholdEvent: DataPacket.ThresholdEvent = batteryStatus.isCritical || (chargeDropedBelowThreshold && !batteryStatus.isCharging) ? .batteryLow : .none
        let packet = DataPacket.batteryPacket(currentCharge: batteryStatus.currentCharge, isCharging: batteryStatus.isCharging, thresholdEvent: thresholdEvent)
        device.send(packet)
    }
    
    private func startMonitoringBatteryState() {
        guard self.runLoopSource == nil else { return }
        
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        let context = UnsafeMutableRawPointer(opaque)
        let source: CFRunLoopSource = IOPSNotificationCreateRunLoopSource(
            PowerSourceChanged,
            context
        ).takeRetainedValue() as CFRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
        
        self.runLoopSource = source
    }
    
    private func stopMonitoringBatteryState() {
        guard let source = self.runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
        self.runLoopSource = nil
        self.lastBatteryStatus = nil
    }
    
    fileprivate func powerSourceChanged() {
        guard let status = getBatteryStatus() else { return }
        for device in self.devices {
            sendBatteryStatus(status, to: device)
        }
        self.lastBatteryStatus = status
    }
}

func PowerSourceChanged(context: UnsafeMutableRawPointer?) {
    let opaque = Unmanaged<BatteryService>.fromOpaque(context!)
    let _self = opaque.takeUnretainedValue()
    _self.powerSourceChanged()
}


// MARK: DataPacket (Battery)

/// Battery service data packet utilities
fileprivate extension DataPacket {
    
    // MARK: Types
    
    enum BatteryError: Error {
        case wrongType
        case invalidRequestFlag
        case invalidChargingFlag
        case invalidCurrentCharge
        case invalidThresholdEvent
    }
    
    struct BatteryProperty {
        static let request = "request"
        static let isCharging = "isCharging"
        static let currentCharge = "currentCharge"
        static let thresholdEvent = "thresholdEvent"
    }
    
    enum ThresholdEvent: Int {
        case none = 0
        case batteryLow = 1
    }
    
    
    // MARK: Properties
    
    static let batteryPacketType = "kdeconnect.battery"
    static let batteryRequestPacketType = "kdeconnect.battery.request"
    
    var isBatteryPacket: Bool { return self.type == DataPacket.batteryPacketType }
    var isBatteryRequestPacket: Bool { return self.type == DataPacket.batteryRequestPacketType }
    
    
    // MARK: Public static methods
    
    static func batteryRequestPacket() -> DataPacket {
        return DataPacket(type: batteryRequestPacketType, body: [
            BatteryProperty.request: true as AnyObject
        ])
    }
    
    static func batteryPacket(currentCharge: Int, isCharging: Bool, thresholdEvent: ThresholdEvent) -> DataPacket {
        return DataPacket(type: batteryPacketType, body: [
            BatteryProperty.currentCharge: currentCharge as AnyObject,
            BatteryProperty.isCharging: isCharging as AnyObject,
            BatteryProperty.thresholdEvent: thresholdEvent.rawValue as AnyObject
        ])

    }
    
    
    // MARK: Public methods
    
    func getRequestFlag() throws -> Bool {
        try self.validateBatteryRequestType()
        guard body.keys.contains(BatteryProperty.request) else { return false }
        guard let value = body[BatteryProperty.request] as? NSNumber else { throw BatteryError.invalidRequestFlag }
        return value.boolValue
    }
    
    func getChargingFlag() throws -> Bool {
        try self.validateBatteryType()
        guard body.keys.contains(BatteryProperty.isCharging) else { return false }
        guard let value = body[BatteryProperty.isCharging] as? NSNumber else { throw BatteryError.invalidChargingFlag }
        return value.boolValue
    }
    
    func getCurrentCharge() throws -> Int {
        try self.validateBatteryType()
        guard body.keys.contains(BatteryProperty.currentCharge) else { return 0 }
        guard let value = body[BatteryProperty.currentCharge] as? NSNumber else { throw BatteryError.invalidChargingFlag }
        return value.intValue
    }
    
    func getThresholdEvent() throws -> ThresholdEvent {
        try self.validateBatteryType()
        guard body.keys.contains(BatteryProperty.thresholdEvent) else { return .none }
        guard let value = body[BatteryProperty.thresholdEvent] as? NSNumber else { throw BatteryError.invalidThresholdEvent }
        guard let thresholdValue = ThresholdEvent(rawValue: value.intValue) else { throw BatteryError.invalidThresholdEvent }
        return thresholdValue
    }
    
    func validateBatteryType() throws {
        guard self.isBatteryPacket else { throw BatteryError.wrongType }
    }
    
    func validateBatteryRequestType() throws {
        guard self.isBatteryRequestPacket else { throw BatteryError.wrongType }
    }
}
