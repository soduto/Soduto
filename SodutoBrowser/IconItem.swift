//
//  IconViewItem.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Cocoa

class IconItem: NSCollectionViewItem {
    
    var iconView: IconItemView? { return self.view as? IconItemView }
    
    var fileItem: FileItem? {
        didSet {
            guard isViewLoaded else { return }
            if let fileItem = self.fileItem, !fileItem.flags.contains(.isDeleted) {
                self.imageView?.image = fileItem.icon
                self.iconView?.label = fileItem.name
                self.iconView?.isHiddenItem = fileItem.flags.contains(.isHidden)
                self.iconView?.isBusy = fileItem.flags.contains(.isBusy)
            } else {
                self.imageView?.image = nil
                self.iconView?.label = ""
                self.iconView?.isHiddenItem = false
                self.iconView?.isBusy = false
            }
            
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.wantsLayer = true
        (self.view as? IconItemView)?.collectionItem = self
    }
    
    override var isSelected: Bool {
        didSet {
            guard self.isSelected != oldValue else { return }
            updateViewSelection()
        }
    }
    
    override var highlightState: NSCollectionViewItemHighlightState {
        didSet {
            guard self.highlightState != oldValue else { return }
            updateViewSelection()
        }
    }
    
    private func updateViewSelection() {
        self.iconView?.isSelected = self.isSelected || self.highlightState == .asDropTarget
    }
    
}
