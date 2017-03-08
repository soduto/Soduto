//
//  BrowserWindowController.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-03.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import AppKit
import CleanroomLogger

class BrowserWindowController: NSWindowController {
    
    // MARK: Properties
    
    public var canGoBack: Bool { return self.window != nil && self.backHistory.count > 0 }
    public var canGoForward: Bool { return self.window != nil && self.forwardHistory.count > 0 }
    public var canGoUp: Bool { return self.window != nil && self.isUrl(self.url, subpathOf: self.fileSystem.rootUrl, strict: true) }
    
    @IBOutlet weak var collectionView: NSCollectionView!
    @IBOutlet weak var iconArrayController: NSArrayController!
    @objc private var icons: [FileItem] = []
    
    private let fileSystem: FileSystem
    private var url: URL
    private var backHistory: [URL] = []
    private var forwardHistory: [URL] = []
    
    override var windowNibName: String! {
        return "BrowserWindow"
    }
    
    
    // MARK: Init / Deinit
    
    init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
        self.url = fileSystem.defaultPlace.url
        
        super.init(window: nil)
        
        // make sure window is loaded
        let _ = self.window
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func windowDidLoad() {
        super.windowDidLoad()
        
        self.collectionView.register(NSNib(nibNamed: "IconItem", bundle: nil), forItemWithIdentifier: "IconItem")
        self.collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        
        goTo(self.fileSystem.defaultPlace.url, updateHistory: false)
    }
    
    
    private func goTo(_ url: URL, updateHistory: Bool = true) {
        guard isUrl(url, subpathOf: self.fileSystem.rootUrl, strict: false) else { return }
        
        if updateHistory {
            self.backHistory.append(self.url)
            self.forwardHistory = []
        }
        
        self.url = url
        self.window?.title = "\(self.fileSystem.name) - \(self.url.lastPathComponent)"
        loadContents()
    }
    
    private func loadContents() {
        let url = self.url
        self.setValue([], forKey: "icons")
        self.collectionView.reloadData()
        self.fileSystem.load(url) { (items, error) in
            if let items = items {
                self.setValue(items, forKey: "icons")
                self.collectionView.reloadData()
            }
            else {
                Log.error?.message("Failed to load items from [\(url)] with error: \(error)")
            }
        }
    }
    
    private func isUrl(_ url1: URL, subpathOf url2: URL, strict: Bool = true) -> Bool {
        guard url1.scheme == url2.scheme else { return false }
        guard url1.host == url2.host else { return false }
        guard url1.port == url2.port else { return false }
        guard url1.user == url2.user else { return false }
        let pathComponents1 = url1.pathComponents
        let pathComponents2 = url2.pathComponents
        guard pathComponents1.count >= pathComponents2.count else { return false }
        guard !strict || pathComponents1.count > pathComponents2.count else { return false }
        for i in 0 ..< pathComponents2.count {
            guard pathComponents1[i] == pathComponents2[i] else { return false }
        }
        return true
    }
    
    
    // MARK: Actions
    
    override func collectionItemViewDoubleClick(_ sender: NSCollectionViewItem) {
        guard let fileItem = (sender as? IconItem)?.fileItem else { return }
        guard fileItem.isDirectory else { return }
        goTo(fileItem.url)
    }
    
    @IBAction func goUp(_ sender: Any?) {
        guard self.canGoUp else { return }
        goTo(self.url.deletingLastPathComponent())
    }
    
    @IBAction func goBack(_ sender: Any?) {
        guard self.canGoBack else { return }
        guard let newUrl = self.backHistory.popLast() else { return }
        self.forwardHistory.append(self.url)
        self.goTo(newUrl, updateHistory: false)
    }
    
    @IBAction func goForward(_ sender: Any?) {
        guard self.canGoForward else { return }
        guard let newUrl = self.forwardHistory.popLast() else { return }
        self.backHistory.append(self.url)
        self.goTo(newUrl, updateHistory: false)
    }
    
    
    // MARK: Menu
    
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.tag {
        case AppDelegate.MenuItemTags.back: return self.canGoBack
        case AppDelegate.MenuItemTags.forward: return self.canGoForward
        case AppDelegate.MenuItemTags.enclosingFolder: return self.canGoUp
        default: return super.validateMenuItem(menuItem)
        }
    }
}

extension BrowserWindowController : NSCollectionViewDataSource {
    
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return (self.iconArrayController.arrangedObjects as? [Any])?.count ?? 0
    }
    
    func collectionView(_ itemForRepresentedObjectAtcollectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        
        let item = collectionView.makeItem(withIdentifier: "IconItem", for: indexPath)
        guard let iconItem = item as? IconItem else { return item }
        guard let objects = self.iconArrayController.arrangedObjects as? [FileItem] else { return item }
        
        iconItem.fileItem = objects[indexPath.item]
        
        return item
    }
    
}

extension BrowserWindowController: NSCollectionViewDelegate {
    
    /* This method is called after it has been determined that a drag should begin, but before the drag has been started. To refuse the drag, return NO. To start the drag, declare the pasteboard types that you support with -[NSPasteboard declareTypes:owner:], place your data for the items at the given index paths on the pasteboard, and return YES from the method. The drag image and other drag related information will be set up and provided by the view once this call returns YES. You need to implement this method, or -collectionView:pasteboardWriterForItemAtIndexPath:, for your collection view to be a drag source.
     */
    public func collectionView(_ collectionView: NSCollectionView, writeItemsAt indexPaths: Set<IndexPath>, to pasteboard: NSPasteboard) -> Bool {
        
        guard let allFileItems = self.iconArrayController.arrangedObjects as? [FileItem] else { return false }
        
        let fileItems = indexPaths.map { return allFileItems[$0.item] }
        
        pasteboard.clearContents()
        pasteboard.writeObjects(fileItems)
        
        return true
    }
    
    
    /* The delegate can support file promise drags by adding NSFilesPromisePboardType to the pasteboard in -collectionView:writeItemsAtIndexPaths:toPasteboard:. NSCollectionView implements -namesOfPromisedFilesDroppedAtDestination: to return the results of this delegate method. This method should return an array of filenames (not full paths) for the created files. The URL represents the drop location. For more information on file promise dragging, see documentation for the NSDraggingSource protocol and -namesOfPromisedFilesDroppedAtDestination:. You do not need to implement this method for your collection view to be a drag source.
     */
//    public func collectionView(_ collectionView: NSCollectionView, namesOfPromisedFilesDroppedAtDestination dropURL: URL, forDraggedItemsAt indexPaths: Set<IndexPath>) -> [String] {
//        
//        guard let fileItems = self.iconArrayController.arrangedObjects as? [FileItem] else { return [] }
//        
//        return fileItems.map { $0.url.lastPathComponent }
//    }
    
    
    /* Allows the delegate to construct a custom dragging image for the items being dragged. 'indexPaths' contains the (section,item) identification of the items being dragged. 'event' is a reference to the  mouse down event that began the drag. 'dragImageOffset' is an in/out parameter. This method will be called with dragImageOffset set to NSZeroPoint, but it can be modified to re-position the returned image. A dragImageOffset of NSZeroPoint will cause the image to be centered under the mouse. You can safely call -[NSCollectionView draggingImageForItemsAtIndexPaths:withEvent:offset:] from within this method. You do not need to implement this method for your collection view to be a drag source.
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, draggingImageForItemsAt indexPaths: Set<IndexPath>, with event: NSEvent, offset dragImageOffset: NSPointPointer) -> NSImage
    
    
    /* This method is used by the collection view to determine a valid drop target. Based on the mouse position, the collection view will suggest a proposed (section,item) index path and drop operation. These values are in/out parameters and can be changed by the delegate to retarget the drop operation. The collection view will propose NSCollectionViewDropOn when the dragging location is closer to the middle of the item than either of its edges. Otherwise, it will propose NSCollectionViewDropBefore. You may override this default behavior by changing proposedDropOperation or proposedDropIndexPath. This method must return a value that indicates which dragging operation the data source will perform. It must return something other than NSDragOperationNone to accept the drop.
     
     Note: to receive drag messages, you must first send -registerForDraggedTypes: to the collection view with the drag types you want to support (typically this is done in -awakeFromNib). You must implement this method for your collection view to be a drag destination.
     
     Multi-image drag and drop: You can set draggingFormation, animatesToDestination, numberOfValidItemsForDrop within this method.
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionViewDropOperation>) -> NSDragOperation
    
    
    /* This method is called when the mouse is released over a collection view that previously decided to allow a drop via the above validateDrop method. At this time, the delegate should incorporate the data from the dragging pasteboard and update the collection view's contents. You must implement this method for your collection view to be a drag destination.
     
     Multi-image drag and drop: If draggingInfo.animatesToDestination is set to YES, you should enumerate and update the dragging items with the proper image components and frames so that they dragged images animate to the proper locations.
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionViewDropOperation) -> Bool
    
    
    /* Multi-image drag and drop */
    
    /* Dragging Source Support - Required for multi-image drag and drop. Return a custom object that implements NSPasteboardWriting (or simply use NSPasteboardItem), or nil to prevent dragging for the item. For each valid item returned, NSCollectionView will create an NSDraggingItem with the draggingFrame equal to the frame of the item view at the given index path and components from -[NSCollectionViewItem draggingItem]. If this method is implemented, then -collectionView:writeItemsAtIndexPaths:toPasteboard: and -collectionView:draggingImageForItemsAtIndexPaths:withEvent:offset: will not be called.
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting?
    
    
    /* Dragging Source Support - Optional. Implement this method to know when the dragging session is about to begin and to potentially modify the dragging session.
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>)
    
    
    /* Dragging Source Support - Optional. Implement this method to know when the dragging session has ended. This delegate method can be used to know when the dragging source operation ended at a specific location, such as the trash (by checking for an operation of NSDragOperationDelete).
     */
//    @available(OSX 10.7, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation)
    
    
    /* Dragging Destination Support - Required for multi-image drag and drop. Implement this method to update dragging items as they are dragged over the view. Typically this will involve calling [draggingInfo enumerateDraggingItemsWithOptions:forView:classes:searchOptions:usingBlock:] and setting the draggingItem's imageComponentsProvider to a proper image based on the NSDraggingItem's -item value.
     */
//    @available(OSX 10.5, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, updateDraggingItemsForDrag draggingInfo: NSDraggingInfo)
    
    
    /* Sent during interactive selection or dragging, to inform the delegate that the CollectionView would like to change the "highlightState" property of the items at the specified "indexPaths" to the specified "highlightState".  In addition to optionally reacting to the proposed change, you can approve it (by returning "indexPaths" as-is), or selectively refuse some or all of the proposed highlightState changes (by returning a modified autoreleased mutableCopy of indexPaths, or an empty indexPaths instance).  Refusing a proposed highlightState change for an item will suppress the associated action for that item (selection change or eligibility to be a drop target).
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, shouldChangeItemsAt indexPaths: Set<IndexPath>, to highlightState: NSCollectionViewItemHighlightState) -> Set<IndexPath>
    
    
    /* Sent during interactive selection or dragging, to inform the delegate that the CollectionView has changed the "highlightState" property of the items at the specified "indexPaths" to the specified "highlightState". */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, didChangeItemsAt indexPaths: Set<IndexPath>, to highlightState: NSCollectionViewItemHighlightState)
    
    
    /* Sent during interactive selection, to inform the delegate that the CollectionView would like to select the items at the specified "indexPaths".  In addition to optionally reacting to the proposed change, you can approve it (by returning "indexPaths" as-is), or selectively refuse some or all of the proposed selection changes (by returning a modified autoreleased mutableCopy of indexPaths, or an empty indexPaths instance).
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath>
    
    
    /* Sent during interactive selection, to inform the delegate that the CollectionView would like to de-select the items at the specified "indexPaths".  In addition to optionally reacting to the proposed change, you can approve it (by returning "indexPaths" as-is), or selectively refuse some or all of the proposed selection changes (by returning a modified autoreleased mutableCopy of indexPaths, or an empty indexPaths instance). */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, shouldDeselectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath>
    
    
    /* Sent at the end of interactive selection, to inform the delegate that the CollectionView has selected the items at the specified "indexPaths".
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>)
    
    
    /* Sent at the end of interactive selection, to inform the delegate that the CollectionView has de-selected the items at the specified "indexPaths".
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>)
    
    
    /* Sent to notify the delegate that the CollectionView is about to add an NSCollectionViewItem.  The indexPath identifies the object that the item represents.
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath)
    
    
    /* Sent to notify the delegate that the CollectionView is about to add a supplementary view (e.g. a section header or footer view).  Each NSCollectionViewLayout class defines its own possible values and associated meanings for "elementKind".  (For example, NSCollectionViewFlowLayout declares NSCollectionElementKindSectionHeader and NSCollectionElementKindSectionFooter.)
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, willDisplaySupplementaryView view: NSView, forElementKind elementKind: String, at indexPath: IndexPath)
    
    
    /* Sent to notify the delegate that the CollectionView is no longer displaying the given NSCollectionViewItem instance.  This happens when the model changes, or when an item is scrolled out of view.  You should perform any actions necessary to help decommission the item (such as releasing expensive resources).  The CollectionView may retain the item instance and later reuse it to represent the same or a different model object.
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath)
    
    
    /* Sent to notify the delegate that the CollectionView is no longer displaying the given supplementary view. This happens when the model changes, or when a supplementary view is scrolled out of view. You should perform any actions necessary to help decommission the view (such as releasing expensive resources). The CollectionView may retain the view and later reuse it. */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, didEndDisplayingSupplementaryView view: NSView, forElementOfKind elementKind: String, at indexPath: IndexPath)
    
    
    /* Sent when the CollectionView switches to a different layout, to allow the delegate to provide a custom transition if desired.
     */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, transitionLayoutForOldLayout fromLayout: NSCollectionViewLayout, newLayout toLayout: NSCollectionViewLayout) -> NSCollectionViewTransitionLayout
    
}
