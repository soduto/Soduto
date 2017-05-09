//
//  CollectionView.swift
//  Soduto
//
//  Created by Giedrius on 2017-05-09.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

class CollectionView: NSCollectionView {
    
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .shift, .option])
        
        if isSelectectionEmty && numberOfSections > 0 && numberOfItems(inSection: 0) > 0 && flags == [] {
            switch event.keyCode {
            case 123: // left
                selectItems(at: [IndexPath(indexes: [numberOfSections-1, numberOfItems(inSection: numberOfSections-1)-1])], scrollPosition: .bottom)
            case 125: // down
                selectItems(at: [IndexPath(indexes: [0, 0])], scrollPosition: .top)
            case 124: // right
                selectItems(at: [IndexPath(indexes: [0, 0])], scrollPosition: .top)
            case 126: // up
                selectItems(at: [IndexPath(indexes: [numberOfSections-1, numberOfItems(inSection: numberOfSections-1)-1])], scrollPosition: .bottom)
            default: break
            }
            return
        }
        
        super.keyDown(with: event)
    }
    
    private var isSelectectionEmty: Bool {
        for indexPath in selectionIndexPaths {
            if indexPath.section < numberOfSections && indexPath.section >= 0 &&
                indexPath.item < numberOfItems(inSection: indexPath.section) && indexPath.item >= 0 {
                return false
            }
        }
        return true
    }
}
