//
//  MenuView.swift
//  Soduto
//
//  Created by Giedrius on 2017-02-19.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

/// TODO: Finish or remove
public class MenuView: NSButton {
    
    // MARK: Properties
    
    private let label: NSTextField
    private let disclosureButton: NSButton
    private let imageView: NSImageView
    private var trackingArea: NSTrackingArea?
    
    // MARK: Init / Deinit
    
    init(menuItem: NSMenuItem) {
        self.label = NSTextField(labelWithString: "abcdefghijklmnopqrstuvzxyzABCDEFGHIJKLMNOPQRSTUVZXYZ")
        self.label.font = menuItem.menu?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize())
        self.disclosureButton = NSButton()
        self.imageView = NSImageView()
//        self.cell = NSMenuItemCell()
//        self.cell.menuItem = menuItem
//        self.cell.title = menuItem.title
//        self.cell.font = self.label.font
        
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: self.label.frame.size.height + 2))
        
        self.isBordered = false
        self.alignment = .natural
        self.setButtonType(.momentaryLight)
        if #available(OSX 10.12.2, *) {
            self.bezelColor = NSColor.selectedMenuItemColor
        }
        self.font = self.label.font
        self.title = menuItem.title
        self.label.stringValue = menuItem.title
//        self.label.frame = self.cell.titleRect(forBounds: self.bounds)
//        self.addSubview(self.label)
//
//        self.addSubview(self.imageView)
//        
//        self.disclosureButton.bezelStyle = .disclosure
//        self.addSubview(self.disclosureButton)
        
        self.autoresizingMask = [.viewWidthSizable, .viewMinYMargin]
    }
    
    public required init?(coder: NSCoder) {
        fatalError("Not available")
    }
    
    
//    override public func draw(_ dirtyRect: NSRect) {
//        super.draw(dirtyRect)
//        
//        if self.isMouseOver {
//            NSColor.selectedMenuItemColor.setFill()
//            NSRectFillUsingOperation(dirtyRect.intersection(self.bounds), .copy)
//        }
//        
////        self.cell.isHighlighted = self.isMouseOver
////        self.cell.drawBorderAndBackground(withFrame: self.bounds, in: self)
////        self.cell.draw(withFrame: self.bounds, in: self)
//    }
    
//    override public func updateTrackingAreas() {
//        super.updateTrackingAreas()
//        
//        if let trackingArea = self.trackingArea {
//            self.removeTrackingArea(trackingArea)
//        }
//        let trackingArea = NSTrackingArea(rect: self.bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: nil, userInfo: nil)
//        self.addTrackingArea(trackingArea)
//        self.trackingArea = trackingArea
//    }
//    
//    override public func mouseEntered(with event: NSEvent) {
//        super.mouseEntered(with: event)
//        self.cell.isHighlighted = true
//        self.setNeedsDisplay(self.bounds)
//    }
//    
//    override public func mouseExited(with event: NSEvent) {
//        super.mouseExited(with: event)
//        self.cell.isHighlighted = false
//        self.setNeedsDisplay(self.bounds)
//    }
    
    override public var allowsVibrancy: Bool {
        return false
    }
    
    
    private var isMouseOver: Bool {
        guard let mouseLocation = self.window?.mouseLocationOutsideOfEventStream else { return false }
        let viewMouseLocation = self.convert(mouseLocation, from: nil)
        return self.bounds.contains(viewMouseLocation)
    }
}
