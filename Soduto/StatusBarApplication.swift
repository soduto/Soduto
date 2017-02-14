//
//  StatusBarApplication.swift
//  Soduto
//
//  Created by Giedrius on 2017-02-03.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

class StatusBarApplication: NSApplication {
    
    override func sendEvent(_ event: NSEvent) {
        if event.type == NSEventType.keyDown {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command] {
                switch event.charactersIgnoringModifiers!.lowercased() {
                case "x":
                    if sendAction(#selector(NSText.cut(_:)), to:nil, from:self) { return }
                case "c":
                    if sendAction(#selector(NSText.copy(_:)), to:nil, from:self) { return }
                case "v":
                    if sendAction(#selector(NSText.paste(_:)), to:nil, from:self) { return }
                case "z":
                    if sendAction(Selector(("undo:")), to:nil, from:self) { return }
                case "a":
                    if sendAction(#selector(NSResponder.selectAll(_:)), to:nil, from:self) { return }
                default:
                    break
                }
            }
            else if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift] {
                if event.charactersIgnoringModifiers?.lowercased() == "z" {
                    if sendAction(Selector(("redo:")), to:nil, from:self) { return }
                }
            }
        }

        return super.sendEvent(event)
    }
    
}
