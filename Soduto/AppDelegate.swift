//
//  AppDelegate.swift
//  Soduto
//
//  Created by Admin on 2016-07-06.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Cocoa
import CleanroomLogger

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, DeviceManagerDelegate {
    
    @IBOutlet weak var statusBarMenuController: StatusBarMenuController!

    let config = Configuration()
    let connectionProvider: ConnectionProvider
    let deviceManager: DeviceManager
    let serviceManager = ServiceManager()
    let userNotificationManager: UserNotificationManager
    
    override init() {
        #if DEBUG
            Log.enable(configuration: XcodeLogConfiguration(minimumSeverity: .debug, logToASL: false))
        #else
            let formatter = FieldBasedLogFormatter(fields: [.severity(.simple), .delimiter(.spacedPipe), .payload])
            let aslRecorder = ASLLogRecorder(formatter: formatter, echoToStdErr: true)
            Log.enable(configuration: BasicLogConfiguration(minimumSeverity: .debug, recorders: [aslRecorder]))
        #endif
        
        
        self.connectionProvider = ConnectionProvider(config: config)
        self.deviceManager = DeviceManager(config: config, serviceManager: self.serviceManager)
        self.userNotificationManager = UserNotificationManager(config: self.config, serviceManager: self.serviceManager, deviceManager: self.deviceManager)
        
        super.init()
        
        self.checkOneAppInstanceRunning()
    }
    
    
    // MARK: NSApplicationDelegate
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        self.config.capabilitiesDataSource = self.serviceManager
        self.connectionProvider.delegate = self.deviceManager
        self.statusBarMenuController.deviceDataSource = self.deviceManager
        self.deviceManager.delegate = self
        
        self.serviceManager.add(service: PingService())
        self.serviceManager.add(service: FindMyPhoneService())
        self.serviceManager.add(service: NotificationsService())
        self.serviceManager.add(service: ClipboardService())
        self.serviceManager.add(service: ShareService())
        self.serviceManager.add(service: TelephonyService())
        
        self.connectionProvider.start()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    
    // MARK: DeviceManagerDelegate
    
    func deviceManager(_ manager: DeviceManager, didChangeDeviceState device: Device) {
        self.statusBarMenuController.refreshDeviceLists()
    }
    
    func deviceManager(_ manager: DeviceManager, didReceivePairingRequest request: PairingRequest, forDevice device: Device) {
        Log.debug?.message("deviceManager(<\(request)> didReceivePairingRequest:<\(request)> forDevice:<\(device)>)")
        PairingInterfaceController.showPairingNotification(for: device)
    }
    
    
    // MARK: Private
    
    private func checkOneAppInstanceRunning() {
        let lockFileName = FileManager.default.temporaryDirectory.appendingPathComponent(self.config.hostDeviceId).appendingPathExtension("lock").path
        if !tryLock(lockFileName) {
            let alert = NSAlert()
            alert.addButton(withTitle: "OK")
            alert.informativeText = NSLocalizedString("Another instance of the app is already running. Exiting", comment: "")
            alert.messageText = Bundle.main.bundleIdentifier?.components(separatedBy: ".").last ?? ""
            alert.runModal()
            NSApp.terminate(self)
        }
    }
    
}

