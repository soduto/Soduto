//
//  TextFieldWithLinks.swift
//  Soduto
//
//  Created by Giedrius on 2017-07-02.
//  Copyright © 2017 Soduto. All rights reserved.
//

//  This is a Swift adaptation of NSTextFieldsHyperlinks class form
//  https://github.com/laevandus/NSTextFieldHyperlinks/blob/master/NSTextFieldHyperlinks/HyperlinkTextField.m
//  with LICENCE information below:
//
//  Created by Toomas Vahter on 25.12.12.
//  Copyright (c) 2012 Toomas Vahter. All rights reserved.
//
//  This content is released under the MIT License (http://www.opensource.org/licenses/mit-license.php).
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


import Foundation
import Cocoa

public class TextFieldWithLinks: NSTextField {
    
    private struct LinkInfo {
        let range: NSRange
        let link: URL
        let rects: [NSRect]
    }
    
    public var transformsMarkdownLinks: Bool = true {
        didSet { handleMarkdownLinks() }
    }
    
    override public func layout() {
        super.layout()
        self.window?.invalidateCursorRects(for: self)
    }
    
    private var textView: NSTextView {
        // Font used for displaying and frame calculations must match
        let string = NSMutableAttributedString(attributedString: self.attributedStringValue)
        if let font = self.font {
            let paragraphStyle = NSMutableParagraphStyle()
            if #available(OSX 10.13, *) {}
            else {
                paragraphStyle.lineSpacing = 1
            }
            string.applyDefaultAttributes([
                NSAttributedStringKey.font: font,
                NSAttributedStringKey.paragraphStyle: paragraphStyle
            ])
        }
        
        let textViewFrame = self.cell?.titleRect(forBounds: self.bounds) ?? NSRect.zero
        let textView = NSTextView(frame: textViewFrame)
        textView.textStorage?.setAttributedString(string)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize.zero
        
        return textView;
    }
    
    private var linkInfos: [LinkInfo] {
        let textView = self.textView
        guard let layoutManager = textView.layoutManager else { return [] }
        guard let textContainer = textView.textContainer else { return [] }
        guard let string = textView.textStorage else { return [] }
        let fullRange = NSMakeRange(0, string.length)
        var infos: [LinkInfo] = []
        
        let image = NSImage(size: bounds.size, flipped: true) { (rect) -> Bool in
            layoutManager.drawGlyphs(forGlyphRange: layoutManager.glyphRange(for: textContainer), at: NSPoint.zero)
            return true
        }
        
        string.enumerateAttribute(NSAttributedStringKey.link, in: fullRange, options: []) { (value, range, stop) in
            guard let url = value as? NSURL else { return }
            
            var rects: [NSRect] = []
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: glyphRange, in: textContainer, using: { (rect, stop) in
                rects.append(rect)
            })
            
            infos.append(LinkInfo(range: range, link: url as URL, rects: rects))
        }
        
        return infos
    }
    
    public override func resetCursorRects() {
        super.resetCursorRects()
        resetLinkCursorRects()
    }
    
    private func resetLinkCursorRects() {
        guard !isEditable && !isSelectable else { return }
        
        for info in self.linkInfos {
            for rect in info.rects {
                addCursorRect(rect, cursor: NSCursor.pointingHand)
            }
        }
    }
    
    override public func mouseUp(with event: NSEvent) {
        if isEditable || isSelectable {
            super.mouseUp(with: event)
            return
        }
        
        let textView = self.textView
        guard let textContainer = textView.textContainer else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        guard let index = textView.layoutManager?.characterIndex(for: localPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil) else { return }
        guard index != NSNotFound else { return }
        
        for info in linkInfos {
            guard info.range.contains(index) else { continue }
            NSWorkspace.shared.open(info.link)
        }
    }
    
    override public func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        guard !isEditable else { return }
        handleMarkdownLinks()
    }
    
    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        handleMarkdownLinks()
    }
    
    private var isHandlingMarkdownLinks: Bool = false
    private func handleMarkdownLinks() {
        guard transformsMarkdownLinks else { return }
        guard !isHandlingMarkdownLinks else { return }
        
        isHandlingMarkdownLinks = true
        defer { isHandlingMarkdownLinks = false }
        
        self.attributedStringValue = self.attributedStringValue.byReplacingMarkdownWithLinks()
        self.window?.invalidateCursorRects(for: self)
    }
    
}

