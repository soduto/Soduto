//
//  IconViewBox.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-03.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import AppKit
import CoreImage

public class IconItemView: NSBox, NSTextFieldDelegate {

    public weak var collectionItem: IconItem!
    
    private dynamic var iconView: NSImageView!
    private dynamic var iconBackgroundView: NSView!
    private dynamic var labelView: NSTextField!
    private dynamic var overlayView: NSImageView!
    
    
    public var label: String = "" {
        didSet {
            self.labelView.stringValue = self.label
        }
    }
    
    public var isSelected: Bool = false {
        didSet { updateStyle() }
    }
    
    public var isHiddenItem: Bool = false {
        didSet { updateStyle() }
    }
    
    public var isBusy: Bool = false {
        didSet { updateStyle() }
    }
    
    public var isEditing: Bool { return self.labelView.currentEditor() != nil }
    
    
    public override func awakeFromNib() {
        super.awakeFromNib()
        
        let iconBackgroundView = self.subviews[0].subviews.first(where: { return !($0 is NSTextField) })
        let iconView = iconBackgroundView?.subviews.first as? NSImageView
        let overlayView = iconBackgroundView?.subviews.last as? NSImageView
        let labelView = self.subviews[0].subviews.first(where: { return $0 is NSTextField }) as? NSTextField
        
        self.iconView = iconView
        self.iconView.unregisterDraggedTypes()
        
        self.iconBackgroundView = iconBackgroundView
        self.iconBackgroundView.wantsLayer = true
        self.iconBackgroundView.layer?.cornerRadius = 3.0
        self.iconBackgroundView.layer?.masksToBounds = true
        
        self.labelView = labelView
        self.labelView.wantsLayer = true
        self.labelView.layer?.cornerRadius = 3.0
        self.labelView.layer?.masksToBounds = true
        self.labelView.allowsExpansionToolTips = true
        self.labelView.maximumNumberOfLines = 2
        self.labelView.delegate = self
        
        self.overlayView = overlayView
        
        updateStyle()
    }
    
    public override func mouseUp(with event: NSEvent) {
        if event.clickCount == 1 {
            if let location = self.superview?.convert(event.locationInWindow, from: nil), hitTest(location) == self.labelView {
                NSApplication.shared().sendAction(#selector(BrowserWindowController.collectionItemViewLabelClick(_:)), to: nil, from: self.collectionItem)
            }
        }
        else if event.clickCount == 2 {
            NSApplication.shared().sendAction(#selector(BrowserWindowController.collectionItemViewDoubleClick(_:)), to: nil, from: self.collectionItem)
        }
        super.mouseUp(with: event)
    }
    
    
    // MARK: Editing
    
    public func startEditing() {
        self.labelView.isEditable = true
        if self.window?.makeFirstResponder(self.labelView) == true {
            updateStyle()
        }
        else {
            self.labelView.isEditable = false
        }
    }
    
    public func cancelEditing() {
        finishEditing()
    }
    
    public override func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSControl) == self.labelView else { assertionFailure("Expected notification from own labelView, but got \(obj.object)"); return }
        if self.labelView.stringValue != self.label {
            self.collectionItem.labelTextDidChange(self.labelView.stringValue)
        }
        finishEditing()
    }
    
    public override func cancelOperation(_ sender: Any?) {
        cancelEditing()
    }
    
    private func finishEditing() {
        self.labelView.abortEditing()
        self.labelView.isEditable = false
        self.labelView.needsUpdateConstraints = true
        updateStyle()
    }
    
    
    // MARK: Other
    
    private func updateStyle() {
        self.iconBackgroundView.layer?.backgroundColor = self.isSelected || self.isEditing ? NSColor.secondarySelectedControlColor.cgColor : nil
        self.labelView.layer?.backgroundColor = self.isSelected && !self.isEditing ? NSColor.alternateSelectedControlColor.cgColor : nil
        self.labelView.textColor = self.isSelected && !self.isEditing ? NSColor.alternateSelectedControlTextColor : nil
        
        if self.isBusy {
            self.iconView.alphaValue = 0.3
            self.iconView.contentFilters = [CIFilter(name: "CIPhotoEffectMono")!]
            self.labelView.alphaValue = 0.6
        }
        else if self.isHiddenItem {
            self.iconView.alphaValue = 0.5
            self.iconView.contentFilters = []
            self.labelView.alphaValue = 0.6
        }
        else {
            self.iconView.alphaValue = 1.0
            self.iconView.contentFilters = []
            self.labelView.alphaValue = 1.0
        }
        
        if self.isBusy {
            self.overlayView.image = #imageLiteral(resourceName: "busyOverlayIcon")
        }
        else {
            self.overlayView.image = nil
        }
    }
}
