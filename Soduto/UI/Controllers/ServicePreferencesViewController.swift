//
//  ServicePreferencesViewController.swift
//  Soduto
//
//  Created by Giedrius on 2017-07-23.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

class ServicePreferencesViewController: NSViewController {
    
    // MARK: Types
    
    private struct ServiceInfo {
        let id: Service.Id
        let name: String
    }
    
    
    // MARK: Properties
    
    var servicesConfiguration: ServicesConfiguartion?
    var deviceDataSource: DeviceDataSource?
    @IBOutlet weak var serviceList: NSTableView!
    
    private let configurableServices: [ServiceInfo] = [
        ServiceInfo(id: ClipboardService.serviceId, name: NSLocalizedString("Clipboard Sharing", comment: "Service name")),
        ServiceInfo(id: NotificationsService.serviceId, name: NSLocalizedString("Notifications", comment: "Service name"))
    ]
    
    
    // MARK: Public API
    
    func refreshDeviceList() {
//        self.deviceList.reloadData()
    }
    
    
    // MARK: NSViewController
    
    override func viewDidLoad() {
        refreshDeviceList()
    }
    
    override func viewWillAppear() {
        // Resize first column to full table width
//        self.deviceList.tableColumns.first?.width = self.deviceList.frame.width - self.deviceList.intercellSpacing.width
    }
}


// MARK: -

extension ServicePreferencesViewController : NSTableViewDataSource {
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        // 1 item always shown for default configuration for all devices
        guard let deviceDataSource = self.deviceDataSource else { return 1 }
        return deviceDataSource.pairedDevices.count + deviceDataSource.unavailableDevices.count + 1
    }
    
}


// MARK: -

extension ServicePreferencesViewController: NSTableViewDelegate {
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        let device: Device?
        if row > 0 {
            guard let deviceDataSource = self.deviceDataSource else { return nil }
            
            var i = row - 1
            if i < deviceDataSource.pairedDevices.count {
                device = deviceDataSource.pairedDevices[i]
            }
            else {
                i = i - deviceDataSource.pairedDevices.count
                if i < deviceDataSource.unavailableDevices.count {
                    device = deviceDataSource.unavailableDevices[i]
                }
                else {
                    return nil
                }
            }
        }
        else {
            device = nil
        }
        
        if let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DeviceItemID"), owner: nil) as? DeviceListItemView {
            view.defaultTextString = NSLocalizedString("Default", comment: "Default config for all devices")
            view.defaultInfoString = NSLocalizedString("All devices", comment: "Default config for all devices")
            view.device = device
            return view
        }
        
        return nil
    }
    
}

