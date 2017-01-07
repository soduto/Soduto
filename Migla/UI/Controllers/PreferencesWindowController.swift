//
//  PreferencesWindowController.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-08-30.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import Cocoa

public class PreferencesWindowController: NSWindowController {
    
    weak var deviceDataSource: DeviceDataSource?
    @IBOutlet weak var deviceList: NSTableView!
    @IBOutlet weak var hostNameLabel: NSTextField!
    
    
    
    static func loadController() -> PreferencesWindowController {
        return PreferencesWindowController(windowNibName: "PreferencesWindow")
    }
    
    
    
    func refreshDeviceList() {
        self.deviceList.reloadData()
    }
    
    override public func showWindow(_ sender: Any?) {
        // make sure window is loaded
        let _ = self.window
        
        NSApp.activate(ignoringOtherApps: true)
        
        self.hostNameLabel.stringValue = Host.current().localizedName ?? "Migla"
        
        super.showWindow(sender)
    }
    
    
    override public func windowDidLoad() {
        self.refreshDeviceList()
    }
}


// MARK: -

extension PreferencesWindowController : NSTableViewDataSource {
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        guard let deviceDataSource = self.deviceDataSource else { return 0 }
        return deviceDataSource.pairedDevices.count + deviceDataSource.unpairedDevices.count + deviceDataSource.unavailableDevices.count
    }

}


// MARK: -

extension PreferencesWindowController: NSTableViewDelegate {
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        guard let deviceDataSource = self.deviceDataSource else { return nil }
        
        let device: Device
        var i = row
        if i < deviceDataSource.pairedDevices.count {
            device = deviceDataSource.pairedDevices[i]
        }
        else {
            i = i - deviceDataSource.pairedDevices.count
            if i < deviceDataSource.unpairedDevices.count {
                device = deviceDataSource.unpairedDevices[i]
            }
            else {
                i = i - deviceDataSource.unpairedDevices.count
                if i < deviceDataSource.unavailableDevices.count {
                    device = deviceDataSource.unavailableDevices[i]
                }
                else {
                    return nil
                }
            }
        }
        
        if let cell = tableView.make(withIdentifier: "DeviceItemID", owner: nil) as? DeviceListItemView {
            cell.device = device
            return cell
        }
        
        return nil
    }
    
}
