//
//  IconViewItem.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Cocoa

public protocol IconItemDelegate: class {
    func iconItem(_ iconItem: IconItem, didChangeName: String)
}

public class IconItem: NSCollectionViewItem {
    
    // MARK: Properties
    
    public weak var delegate: IconItemDelegate?
    
    public var iconView: IconItemView? { return self.view as? IconItemView }
    
    public var fileItem: FileItem? {
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
    
    public override var isSelected: Bool {
        didSet {
            guard self.isSelected != oldValue else { return }
            updateViewSelection()
        }
    }
    
    public override var highlightState: NSCollectionViewItemHighlightState {
        didSet {
            guard self.highlightState != oldValue else { return }
            updateViewSelection()
        }
    }
    
    private func updateViewSelection() {
        self.iconView?.isSelected = self.isSelected || self.highlightState == .asDropTarget
    }
    
    
    // MARK: Setup / Cleanup
    
    deinit {
        cancelEditing()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.wantsLayer = true
        (self.view as? IconItemView)?.collectionItem = self
    }
    
    
    // MARK: Editing
    
    public var isEditing: Bool { return self.iconView?.isEditing ?? false }
    
    public func startEditing() { self.iconView?.startEditing() }
    
    public func cancelEditing() { self.iconView?.cancelEditing() }
    
    /// Called by the view when edited text changes
    public func labelTextDidChange(_ text: String) {
        self.delegate?.iconItem(self, didChangeName: text)
        self.iconView?.cancelEditing()
    }
    
}
