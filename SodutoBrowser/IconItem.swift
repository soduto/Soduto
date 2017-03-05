//
//  IconViewItem.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Cocoa

class IconItem: NSCollectionViewItem {
    
    var fileItem: FileItem? {
        didSet {
            guard isViewLoaded else { return }
            if let fileItem = self.fileItem {
                self.imageView?.image = fileItem.icon
                self.textField?.stringValue = fileItem.name
            } else {
                self.imageView?.image = nil
                self.textField?.stringValue = ""
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
            (self.view as? IconItemView)?.isSelected = self.isSelected
        }
    }
    
}
