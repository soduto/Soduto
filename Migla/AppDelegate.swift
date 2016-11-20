//
//  AppDelegate.swift
//  Migla
//
//  Created by Admin on 2016-07-06.
//  Copyright © 2016 Migla. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, DeviceManagerDelegate, NSUserNotificationCenterDelegate {
    
    @IBOutlet weak var statusBarMenuController: StatusBarMenuController!

    let config = Configuration()
    let connectionProvider: ConnectionProvider
    let deviceManager: DeviceManager
    let serviceManager = ServiceManager()
    
    override init() {
        self.connectionProvider = ConnectionProvider(config: config)
        self.deviceManager = DeviceManager(config: config, serviceManager: self.serviceManager)
        
        super.init()
    }
    
    
    // MARK: NSApplicationDelegate
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        self.config.capabilitiesDataSource = self.serviceManager
        self.connectionProvider.delegate = self.deviceManager
        self.statusBarMenuController.deviceDataSource = self.deviceManager
        self.deviceManager.delegate = self
        
        self.serviceManager.add(service: PingService())
        self.serviceManager.add(service: FindMyPhoneService())
        
        NSUserNotificationCenter.default.delegate = self
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    
    // MARK: DeviceManagerDelegate
    
    func deviceManager(_ manager: DeviceManager, didChangeDeviceState device: Device) {
        self.statusBarMenuController.refreshDeviceLists()
    }
    
    func deviceManager(_ manager: DeviceManager, didReceivePairingRequest request: PairingRequest, forDevice device: Device) {
        Swift.print("AppDelegate.deviceManager:didReceivePairingRequest:forDevice: \(request) \(device)")
        
        device.acceptPairing()
    }
    
    
    // MARK: NSUserNotificationCenterDelegate
    
    public func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
    
    public func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        NSUserNotificationCenter.default.removeDeliveredNotification(notification)
    }
    
}

