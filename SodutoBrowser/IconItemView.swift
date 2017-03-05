//
//  IconViewBox.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-03.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import AppKit

public class IconItemView: NSBox {

    public weak var collectionItem: NSCollectionViewItem!
    
    private var iconBackgroundView: NSView!
    private var labelView: NSTextField!
    open override var toolTip: String? {
        get { return labelView.stringValue }
        set {}
    }
    
    
    public dynamic var isSelected: Bool = false {
        didSet {
            self.iconBackgroundView.layer?.backgroundColor = self.isSelected ? NSColor.secondarySelectedControlColor.cgColor : nil
            self.labelView.layer?.backgroundColor = self.isSelected ? NSColor.alternateSelectedControlColor.cgColor : nil
            self.labelView.textColor = self.isSelected ? NSColor.alternateSelectedControlTextColor : nil
        }
    }
    
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        guard newWindow != nil else { return }
        
        let iconBackgroundView = self.subviews[0].subviews.first(where: { return !($0 is NSTextField) })
        let labelView = self.subviews[0].subviews.first(where: { return $0 is NSTextField })as? NSTextField
        
        self.iconBackgroundView = iconBackgroundView
        self.iconBackgroundView.wantsLayer = true
        self.iconBackgroundView.layer?.cornerRadius = 3.0
        self.iconBackgroundView.layer?.masksToBounds = true
        
        self.labelView = labelView
        self.labelView.wantsLayer = true
        self.labelView.layer?.cornerRadius = 3.0
        self.labelView.layer?.masksToBounds = true
    }
    
    public override func hitTest(_ aPoint: NSPoint) -> NSView? {
        // don't allow any mouse clicks for subviews in this NSBox
        return super.hitTest(aPoint) != nil ? self : nil
    }
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            NSApplication.shared().sendAction(#selector(collectionItemViewDoubleClick(_:)), to: nil, from: self.collectionItem)
        }
    }
}

extension NSResponder {
    func collectionItemViewDoubleClick(_ sender: NSCollectionViewItem) {
        nextResponder?.collectionItemViewDoubleClick(sender)
    }
}
