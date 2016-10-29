//
//  StatusBarMenuController.swift
//  Migla
//
//  Created by Giedrius Stanevicius on 2016-07-26.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import AppKit

public class StatusBarMenuController: NSObject {
    
    @IBOutlet weak var statusBarMenu: NSMenu!
    @IBOutlet weak var pairedDevicesItem: NSMenuItem!
    @IBOutlet weak var unpairedDevicesItem: NSMenuItem!
    
    public var deviceDataSource: DeviceDataSource?
    
    let statusBarItem = NSStatusBar.system().statusItem(withLength: NSSquareStatusItemLength)
    
    var preferencesWindowController: PreferencesWindowController?
    
    override public func awakeFromNib() {
        let statusBarIcon = #imageLiteral(resourceName: "statusBarIcon")
        statusBarIcon.isTemplate = true
        
        self.statusBarItem.image = statusBarIcon
        self.statusBarItem.menu = statusBarMenu
    }
    
    
    
    @IBAction func quit(_ sender: AnyObject?) {
        NSApp.terminate(sender)
    }
    
    @IBAction func openPreferences(_ sender: AnyObject?) {
        if self.preferencesWindowController == nil {
            self.preferencesWindowController = PreferencesWindowController.loadController()
            self.preferencesWindowController!.deviceDataSource = self.deviceDataSource
        }
        self.preferencesWindowController?.showWindow(nil)
    }
    
    
    
    func refreshDeviceLists() {
        self.preferencesWindowController?.refreshDeviceList()
    }
    
}
