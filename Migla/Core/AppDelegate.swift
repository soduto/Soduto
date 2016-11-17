//
//  AppDelegate.swift
//  Migla
//
//  Created by Admin on 2016-07-06.
//  Copyright © 2016 Migla. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, DeviceManagerDelegate {
    
    @IBOutlet weak var statusBarMenuController: StatusBarMenuController!

    let config = Configuration()
    let connectionProvider: ConnectionProvider
    let deviceManager: DeviceManager
    
    override init() {
        self.connectionProvider = ConnectionProvider(config: config)
        self.deviceManager = DeviceManager(config: config)
        
        super.init()
    }
    
    
    // MARK: NSApplicationDelegate
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        self.connectionProvider.delegate = self.deviceManager
        self.statusBarMenuController.deviceDataSource = self.deviceManager
        self.deviceManager.delegate = self
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
    
}

