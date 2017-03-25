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

public class IconItemView: NSBox {

    public weak var collectionItem: NSCollectionViewItem!
    
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
        
        self.overlayView = overlayView
        
        updateStyle()
    }
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            NSApplication.shared().sendAction(#selector(collectionItemViewDoubleClick(_:)), to: nil, from: self.collectionItem)
        }
    }
    
    
    private func updateStyle() {
        self.iconBackgroundView.layer?.backgroundColor = self.isSelected ? NSColor.secondarySelectedControlColor.cgColor : nil
        self.labelView.layer?.backgroundColor = self.isSelected ? NSColor.alternateSelectedControlColor.cgColor : nil
        self.labelView.textColor = self.isSelected ? NSColor.alternateSelectedControlTextColor : nil
        
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

extension NSResponder {
    func collectionItemViewDoubleClick(_ sender: NSCollectionViewItem) {
        nextResponder?.collectionItemViewDoubleClick(sender)
    }
}
