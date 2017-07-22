//
//  PreferencesWindowController.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-08-30.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import Cocoa

public class PreferencesWindowController: NSWindowController {
    
    var deviceDataSource: DeviceDataSource? {
        didSet { self.devicePreferencesViewController?.deviceDataSource = self.deviceDataSource }
    }
    var config: HostConfiguration? {
        didSet { self.devicePreferencesViewController?.config = self.config }
    }
    
    var devicePreferencesViewController: DevicePreferencesViewController? {
        assert(self.contentViewController is DevicePreferencesViewController)
        return self.contentViewController as? DevicePreferencesViewController
    }
    
    static func loadController() -> PreferencesWindowController {
        let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "PreferencesWindow"), bundle: nil)
        return storyboard.instantiateInitialController() as! PreferencesWindowController
    }
    
    func refreshDeviceList() {
        self.devicePreferencesViewController?.refreshDeviceList()
    }
    
    public override func windowDidLoad() {
        super.windowDidLoad()
        
        self.devicePreferencesViewController?.deviceDataSource = self.deviceDataSource
        self.devicePreferencesViewController?.config = self.config
    }
    
    public override func showWindow(_ sender: Any?) {
        // make sure window is loaded
        let _ = self.window
        
        NSApp.activate(ignoringOtherApps: true)
        
        super.showWindow(sender)
    }
    
}
