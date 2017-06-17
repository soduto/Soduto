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
    var welcomeWindowController: WelcomeWindowController?

    let config = Configuration()
    let connectionProvider: ConnectionProvider
    let deviceManager: DeviceManager
    let serviceManager = ServiceManager()
    let userNotificationManager: UserNotificationManager
    
    static let logLevelConfigurationKey = "com.soduto.logLevel"
    
    override init() {
        UserDefaults.standard.register(defaults: [AppDelegate.logLevelConfigurationKey: LogSeverity.info.rawValue])
        
        #if DEBUG
            Log.enable(configuration: XcodeLogConfiguration(minimumSeverity: .debug, logToASL: false))
        #else
            let formatter = FieldBasedLogFormatter(fields: [.severity(.simple), .delimiter(.spacedPipe), .payload])
            let aslRecorder = ASLLogRecorder(formatter: formatter, echoToStdErr: true)
            let severity: LogSeverity = LogSeverity(rawValue: UserDefaults.standard.integer(forKey: AppDelegate.logLevelConfigurationKey)) ?? .info
            Log.enable(configuration: BasicLogConfiguration(minimumSeverity: severity, recorders: [aslRecorder]))
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
        self.statusBarMenuController.serviceManager = self.serviceManager
        self.statusBarMenuController.config = self.config
        self.deviceManager.delegate = self
        
        //self.serviceManager.add(service: NotificationsService())
        self.serviceManager.add(service: ClipboardService())
        self.serviceManager.add(service: SftpService())
        self.serviceManager.add(service: ShareService())
        self.serviceManager.add(service: TelephonyService())
        self.serviceManager.add(service: PingService())
        self.serviceManager.add(service: BatteryService())
        self.serviceManager.add(service: FindMyPhoneService())
        self.serviceManager.add(service: RemoteKeyboardService())
        
        self.connectionProvider.start()
        
        showWelcomeWindow()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    
    // MARK: DeviceManagerDelegate
    
    func deviceManager(_ manager: DeviceManager, didChangeDeviceState device: Device) {
        self.statusBarMenuController.refreshDeviceLists()
        self.welcomeWindowController?.deviceDataSource = self.deviceManager
    }
    
    func deviceManager(_ manager: DeviceManager, didReceivePairingRequest request: PairingRequest, forDevice device: Device) {
        Log.debug?.message("deviceManager(<\(request)> didReceivePairingRequest:<\(request)> forDevice:<\(device)>)")
        PairingInterfaceController.showPairingNotification(for: device)
    }
    
    
    // MARK: Private
    
    private func checkOneAppInstanceRunning() {
        let lockFileName = FileManager.default.compatTemporaryDirectory.appendingPathComponent(self.config.hostDeviceId).appendingPathExtension("lock").path
        if !tryLock(lockFileName) {
            let alert = NSAlert()
            alert.addButton(withTitle: "OK")
            alert.informativeText = NSLocalizedString("Another instance of the app is already running. Exiting", comment: "")
            alert.messageText = Bundle.main.bundleIdentifier?.components(separatedBy: ".").last ?? ""
            alert.runModal()
            NSApp.terminate(self)
        }
    }
    
    private func showWelcomeWindow() {
        let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "WelcomeWindow"), bundle: nil)
        guard let controller = storyboard.instantiateInitialController() as? WelcomeWindowController else { assertionFailure("Could not load welcome window controller."); return }
        
        NSApp.activate(ignoringOtherApps: true)
        
        controller.deviceDataSource = self.deviceManager
        controller.showWindow(nil)
        self.welcomeWindowController = controller
    }
    
    
    
//    let serviceUUID: UUID = UUID(uuidString: "185f3df4-3268-4e3f-9fca-d4d5059915bd")!
//    var inquiry: IOBluetoothDeviceInquiry?
//
//    private func checkBluetooth() {
//        inquiry = IOBluetoothDeviceInquiry(delegate: self)
//
//        inquiry?.inquiryLength = 15
//        guard inquiry?.start() == kIOReturnSuccess else { Log.error?.message("Failed to start BT inquiry"); return }
//        _ = Timer.compatScheduledTimer(withTimeInterval: 20, repeats: true) { (timer) in
//            guard self.inquiry?.stop() == kIOReturnSuccess else { Log.error?.message("Failed to stop BT inquiry"); return }
//            guard self.inquiry?.start() == kIOReturnSuccess else { Log.error?.message("Failed to start BT inquiry"); return }
//        }
//    }
}

//extension AppDelegate: IOBluetoothDeviceInquiryDelegate {
//
//    @objc dynamic func deviceInquiryStarted(_ sender: IOBluetoothDeviceInquiry!) {
//        Log.info?.message("Searching Bluetooth devices.")
//    }
//
//    @objc dynamic func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
//        Log.info?.message("Found Bluetooth device: \(device)")
//    }
//
//    @objc dynamic func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
//        Log.info?.message("Found Bluetooth devices: \(sender.foundDevices())")
//    }
//}

