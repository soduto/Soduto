//
//  DeviceListItemView.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-09-01.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import Cocoa

public class DeviceListItemView: NSTableCellView {
    
    @IBOutlet weak var infoLabel: NSTextField!
    @IBOutlet weak var actionButton: NSButton!
    
    @IBAction func actionButtonAction(sender: NSButton) {
        guard let device = self.device else { return }
        
        switch device.pairingStatus {
        case .Unpaired:
            device.requestPairing()
            break
        case .Paired:
            device.unpair()
            break
        default:
            break
        }
    }
    
    var device: Device? {
        didSet {
            if let device = self.device {
                self.textField?.stringValue = device.name
                self.textField?.textColor = device.state == .unavailable ? NSColor.disabledControlTextColor : NSColor.controlTextColor
                self.textField?.alphaValue = device.state == .unavailable ? 0.5 : 1.0
                
                let deviceTypeInfo = device.type != .Unknown ? NSLocalizedString(device.type.rawValue, comment: "Device type") : ""
                let deviceStatusInfo = device.state == .unavailable ? NSLocalizedString("unreachable", comment: "Device status") : NSLocalizedString("reachable", comment: "Device status")
                self.infoLabel.stringValue = deviceTypeInfo.isEmpty ? deviceStatusInfo : "\(deviceTypeInfo) - \(deviceStatusInfo)"
                self.infoLabel?.alphaValue = device.state == .unavailable ? 0.5 : 1.0
                
                self.actionButton.title = device.pairingStatus == .Paired ? NSLocalizedString("Unpair", comment: "action") : NSLocalizedString("Pair", comment: "action")
                self.actionButton.isEnabled = device.state != .pairing
                self.actionButton.isHidden = false
                
                switch device.type {
                case .Desktop:
                    self.imageView?.image = #imageLiteral(resourceName: "desktopIcon")
                    break
                case .Laptop:
                    self.imageView?.image = #imageLiteral(resourceName: "laptopIcon")
                    break
                case .Tablet:
                    self.imageView?.image = #imageLiteral(resourceName: "tabletIcon")
                    break
                case .Phone:
                    self.imageView?.image = #imageLiteral(resourceName: "phoneIcon")
                    break
                default:
                    self.imageView?.image = nil
                    break
                }
                self.imageView?.alphaValue = device.state == .unavailable ? 0.5 : 1.0
            }
            else {
                self.textField?.stringValue = ""
                self.infoLabel.stringValue = ""
                self.actionButton.isHidden = true
                self.imageView?.isHidden = true
            }
        }
    }
    
}
