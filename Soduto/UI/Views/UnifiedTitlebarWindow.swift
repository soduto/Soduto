//
//  UnifiedTitlebarWindow.swift
//  Soduto
//
//  Created by Giedrius on 2017-02-02.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

class UnifiedTitlebarWindow: NSWindow {
    
    @IBOutlet weak var titleLabel: NSTextField?
    
    override init(contentRect: NSRect, styleMask style: NSWindowStyleMask, backing bufferingType: NSBackingStoreType, defer flag: Bool) {
        
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        
        self.titleVisibility = .hidden
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitleLabel(notification:)), name: NSNotification.Name.NSWindowDidBecomeKey, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitleLabel(notification:)), name: NSNotification.Name.NSWindowDidResignKey, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitleLabel(notification:)), name: NSNotification.Name.NSApplicationDidBecomeActive, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitleLabel(notification:)), name: NSNotification.Name.NSApplicationDidResignActive, object: self)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func order(_ place: NSWindowOrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        
        titleLabel?.stringValue = title
    }
    
    dynamic private func updateTitleLabel(notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard window === self else { return }
        titleLabel?.textColor = NSApp.isActive && self.isKeyWindow ? NSColor.windowFrameTextColor : NSColor.windowFrameTextColor
    }
}
