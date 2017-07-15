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
    
    var device: Device? {
        didSet {
            if let device = self.device {
                self.textField?.stringValue = device.name
                self.textField?.alphaValue = device.isReachable ? 1.0 : 0.5
                
                let deviceTypeInfo: String = device.type != .Unknown ? NSLocalizedString(device.type.rawValue, comment: "Device type") : ""
                let deviceStatusInfo: String = device.isReachable ? NSLocalizedString("reachable", comment: "Device status") : NSLocalizedString("unreachable", comment: "Device status")
                self.infoLabel?.stringValue = deviceTypeInfo.isEmpty ? deviceStatusInfo : "\(deviceTypeInfo) - \(deviceStatusInfo)"
                self.infoLabel?.alphaValue = device.isReachable ? 0.8 : 0.4
                
                self.actionButton?.title = device.pairingStatus == .Paired ? NSLocalizedString("Unpair", comment: "action") : NSLocalizedString("Pair", comment: "action")
                self.actionButton?.isEnabled = device.pairingStatus != .Requested && device.pairingStatus != .RequestedByPeer
                self.actionButton?.isHidden = false
                
                self.imageView?.image = device.type.icon?.copy() as? NSImage
                self.imageView?.image?.isTemplate = true
                self.imageView?.alphaValue = device.isReachable ? 0.8 : 0.4
            }
            else {
                self.textField?.stringValue = ""
                self.infoLabel?.stringValue = ""
                self.actionButton?.isHidden = true
                self.imageView?.isHidden = true
            }
        }
    }
    
    var displayInfo: ((Device)->Void)?
    
    @IBOutlet weak var infoLabel: NSTextField?
    @IBOutlet weak var actionButton: NSButton?
    
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
    
}

extension DeviceType {
    
    public var icon: NSImage? {
        switch self {
        case .Desktop: return #imageLiteral(resourceName: "desktopIcon")
        case .Laptop: return #imageLiteral(resourceName: "laptopIcon")
        case .Tablet: return #imageLiteral(resourceName: "tabletIcon")
        case .Phone: return #imageLiteral(resourceName: "phoneIcon")
        default: return nil
        }
    }
    
}
