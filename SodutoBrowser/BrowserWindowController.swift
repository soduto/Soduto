//
//  BrowserWindowController.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-03.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa
import CleanroomLogger

protocol BrowserWindowControllerDelegate: class {
    func browserWindowWillClose(_ controller: BrowserWindowController)
}

class BrowserWindowController: NSWindowController {
    
    // MARK: Types
    
    private struct SettingKeys {
        static let showHiddenFiles = "com.soduto.SodutoBrowser.showHiddenFiles"
        static let foldersAlwaysFirst = "com.soduto.SodutoBrowser.foldersAlwaysFirst"
        static let iconsSize = "com.soduto.SodutoBrowser.iconsSize"
    }
    
    
    // MARK: Properties
    
    public weak var delegate: BrowserWindowControllerDelegate?
    
    public var canGoBack: Bool { return self.window != nil && self.backHistory.count > 0 }
    public var canGoForward: Bool { return self.window != nil && self.forwardHistory.count > 0 }
    public var canGoUp: Bool { return self.window != nil && self.fileSystem.isUnderRoot(url) }
    
    public var isHiddenFilesVisible: Bool = BrowserWindowController.userDefaults.bool(forKey: SettingKeys.showHiddenFiles) {
        didSet {
            guard isHiddenFilesVisible != oldValue else { return }
            UserDefaults.standard.set(isHiddenFilesVisible, forKey: SettingKeys.showHiddenFiles)
            updateFilter()
        }
    }
    public var isFoldersAlwaysFirst: Bool = BrowserWindowController.userDefaults.bool(forKey: SettingKeys.foldersAlwaysFirst) {
        didSet {
            guard isFoldersAlwaysFirst != oldValue else { return }
            UserDefaults.standard.set(isFoldersAlwaysFirst, forKey: SettingKeys.foldersAlwaysFirst)
            updateSorting()
        }
    }
    public var iconsSize: Int = BrowserWindowController.userDefaults.integer(forKey: SettingKeys.iconsSize) {
        didSet {
            guard iconsSize != oldValue else { return }
            UserDefaults.standard.set(iconsSize, forKey: SettingKeys.iconsSize)
            updateIconsSize()
        }
    }
    
    @IBOutlet weak var collectionView: NSCollectionView!
    @IBOutlet weak var itemArrayController: NSArrayController!
    @IBOutlet weak var iconsSizeSlider: NSSlider!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var pathControl: NSPathControl!
    
    @objc private var items: [FileItem] = [] {
        didSet {
            updateBusyItems()
            self.itemArrayController.content = self.items
        }
    }
    fileprivate var arrangedItems: [FileItem] {
        guard let items = self.itemArrayController.arrangedObjects as? [FileItem] else { assertionFailure("arrangedObjects could not be converted into array of FileItem"); return [] }
        return items
    }
    private var freeSpace: Int64?
    
    public let fileSystem: FileSystem
    public private(set) var url: URL
    private var backHistory: [URL] = []
    private var forwardHistory: [URL] = []
    private var busyURLs: Set<URL> = []
    private var fileOperationsQueue: OperationQueue = OperationQueue()
    private var isLoadingContents: Bool = false
    
    override var windowNibName: NSNib.Name! { return NSNib.Name(rawValue: "BrowserWindow") }
    
    fileprivate static let dropTypes: [NSPasteboard.PasteboardType] = [ NSPasteboard.PasteboardType(rawValue: kUTTypeURL as String) ]
    private static var userDefaults: UserDefaults = {
        // Setup user settings default values
        UserDefaults.standard.register(defaults: [
            SettingKeys.showHiddenFiles: false,
            SettingKeys.foldersAlwaysFirst: true,
            SettingKeys.iconsSize: 48
            ])
        
        return UserDefaults.standard
    }()
    
    
    // MARK: Setup / Cleanup
    
    init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
        self.url = fileSystem.defaultPlace.url
        
        super.init(window: nil)
        
        self.fileSystem.delegate = self
        self.fileOperationsQueue.underlyingQueue = DispatchQueue.main
         
        // make sure window is loaded
        let _ = self.window
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func windowDidLoad() {
        super.windowDidLoad()
        
        self.window?.delegate = self
        let autosaveNameID = self.fileSystem.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        self.window?.setFrameAutosaveName(NSWindow.FrameAutosaveName(rawValue: "com.soduto.SodutoBrowser.window-\(autosaveNameID)"))
        self.window?.makeKey()
        
        let iconItemNib = NSNib(nibNamed: NSNib.Name(rawValue: "IconItem"), bundle: nil)
        self.collectionView.register(iconItemNib, forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "IconItem"))
        self.collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        self.collectionView.registerForDraggedTypes(type(of: self).dropTypes)
        
        updateFilter()
        updateSorting()
        updateIconsSize()
        updateStatusInfo()
        
        goTo(self.fileSystem.defaultPlace.url, updateHistory: false)
    }
    
    
    // MARK: Contents handling
    
    private func goTo(_ url: URL, updateHistory: Bool = true) {
        guard self.fileSystem.isOwn(url) else { return }
        guard url.hasDirectoryPath else { return }
        
        if updateHistory {
            self.backHistory.append(self.url)
            self.forwardHistory = []
        }
        
        self.url = url
        self.window?.toolbar?.items.forEach { $0.isEnabled = self.validateToolbarItem($0) }
        loadContents()
        updateWindowTitle()
        updatePathControl()
    }
    
    private func loadContents() {
        let url = self.url
        self.isLoadingContents = true
        self.items = []
        self.collectionView.reloadData()
        updateProgress()
        updateStatusInfo()
        
        self.fileSystem.load(url) { (items, freeSpace, error) in
            self.isLoadingContents = false
            self.updateProgress()
            if let items = items {
                self.items = items
                self.freeSpace = freeSpace
                self.collectionView.reloadData()
                self.updateStatusInfo()
            }
            else {
                Log.error?.message("Failed to load items from [\(url)] with error: \(String(describing: error))")
            }
        }
    }
    
    private func updateWindowTitle() {
        if self.fileSystem.isUnderRoot(self.url) {
            self.window?.title = "\(self.fileSystem.name) - \(self.url.lastPathComponent)"
        }
        else {
            self.window?.title = self.fileSystem.name
        }
    }
    
    private func updateIconsSize() {
        var size = NSSize(width: self.iconsSize, height: self.iconsSize)
        size.height += 50 // Additional space for label and paddings
        size.width += 8 // Image padding
        size.width = max(size.width, 120)
        (self.collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize = size
        self.iconsSizeSlider.integerValue = self.iconsSize
    }
    
    fileprivate func updateStatusInfo() {
        let itemsCountStr: String
        if self.collectionView.selectionIndexes.count > 0 {
            itemsCountStr = String(format: NSLocalizedString("%d of %d selected", comment: ""), self.collectionView.selectionIndexes.count, self.arrangedItems.count)
        }
        else {
            itemsCountStr = String(format: NSLocalizedString("%d items", comment: ""), self.arrangedItems.count)
        }
        
        let statusStr: String
        if let freeSpace = self.freeSpace {
            let freeSpaceStr = String(format: NSLocalizedString("%@ available", comment: ""), ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file))
            statusStr = "\(itemsCountStr), \(freeSpaceStr)"
        }
        else {
            statusStr = itemsCountStr
        }
        
        self.statusLabel.stringValue = statusStr
    }
    
    fileprivate func updatePathControl() {
        var cells: [NSPathComponentCell] = []
        var url = self.fileSystem.rootUrl
        
        let rootCell = NSPathComponentCell()
        rootCell.image = NSImage(named: NSImage.Name.network)
        rootCell.title = self.fileSystem.name
        rootCell.url = url
        cells.append(rootCell)
        
        let relativePath = self.url.relativeTo(self.fileSystem.rootUrl).rebasing(to: URL(string: "/")!)
        for component in relativePath.pathComponents {
            guard component != "/" else { continue }
            url.appendPathComponent(component, isDirectory: true)
            let cell = NSPathComponentCell()
            cell.image = NSImage(named: NSImage.Name.folder)
            cell.title = component
            cell.url = url
            cells.append(cell)
        }
        
        if self.collectionView.selectionIndexPaths.count == 1, let fileItem = self.fileItem(at: self.collectionView.selectionIndexPaths.first!), fileItem.isDirectory {
            let cell = NSPathComponentCell()
            cell.image = NSImage(named: NSImage.Name.folder)
            cell.title = fileItem.name
            cell.url = fileItem.url
            cells.append(cell)
        }
        
        self.pathControl.setPathComponentCells(cells)
    }
    
    private func updateProgress() {
        if self.isLoadingContents || self.fileOperationsQueue.operationCount > 0 {
            self.progressIndicator.startAnimation(self)
        }
        else {
            self.progressIndicator.stopAnimation(self)
        }
    }
    
    private func updateFilter() {
        self.itemArrayController.filterPredicate = NSPredicate(block: { (item, substitutions) -> Bool in
            guard let fileItem = item as? FileItem else { return false }
            guard !fileItem.isHidden || self.isHiddenFilesVisible else { return false }
            return true
        })
        self.collectionView.reloadData()
        updateStatusInfo()
    }
    
    private func updateSorting() {
        var descriptors: [NSSortDescriptor] = []
        if isFoldersAlwaysFirst {
            descriptors.append(NSSortDescriptor(key: "isDirectory", ascending: false))
        }
        self.itemArrayController.sortDescriptors = descriptors
        self.collectionView.reloadData()
        updateStatusInfo()
    }
    
    private func updateBusyItems() {
        guard !isLoadingContents else { return } // we dont want to add busy items suring loadin new content - only after it is loaded
        
        var usedURLs = Set<URL>()
        for item in self.items {
            if self.busyURLs.contains(item.url) {
                item.dynamicFlags.insert(.isBusy)
                usedURLs.insert(item.url)
            }
        }
        
        let unusedBusyURLs = busyURLs.subtracting(usedURLs)
        for busyURL in unusedBusyURLs {
            guard busyURL.deletingLastPathComponent() == self.url else { continue }
            let fileItem = FileItem(url: busyURL)
            self.items.append(fileItem)
        }
    }
    
    fileprivate func isValid(_ indexPath: IndexPath) -> Bool {
        guard indexPath.section == 0 else { return false }
        guard indexPath.item < items.count else { return false }
        return true
    }
    
    fileprivate func fileItem(at indexPath: IndexPath) -> FileItem? {
        guard indexPath.section == 0 else { assertionFailure("Only one index path section supported."); return nil }
        let items = self.arrangedItems
        guard indexPath.item < items.count else { assertionFailure("index path with (\(indexPath.section), \(indexPath.item)) is out of arrangedItems bounds (0..<\(items.count))"); return nil }
        return items[indexPath.item]
    }
    
    fileprivate func fileItems(at indexPaths: Set<IndexPath>) -> [FileItem] {
        return indexPaths.flatMap { return self.fileItem(at: $0) }
    }
    
    fileprivate func indexPath(for url: URL) -> IndexPath? {
        guard let index =  self.arrangedItems.index(where: { $0.url == url }) else { return nil }
        return IndexPath(indexes: [0, index])
    }
    
    fileprivate func indexPath(for fileItem: FileItem) -> IndexPath? {
        return indexPath(for: fileItem.url)
    }
    
    fileprivate func indexPaths<T: Collection>(for urls: T) -> Set<IndexPath> where T.Iterator.Element == URL {
        var paths: Set<IndexPath> = []
        let arrangedItems = self.arrangedItems
        for i in 0 ..< arrangedItems.count {
            let url = arrangedItems[i].url
            guard urls.contains(where: { $0 == url }) else { continue }
            paths.insert(IndexPath(indexes: [0, i]))
        }
        return paths
    }
    
    fileprivate func indexPaths<T: Collection>(for fileItems: T) -> Set<IndexPath> where T.Iterator.Element == FileItem {
        var paths: Set<IndexPath> = []
        let arrangedItems: [FileItem] = (self.itemArrayController.arrangedObjects as? [FileItem]) ?? []
        for i in 0 ..< arrangedItems.count {
            let url = arrangedItems[i].url
            guard fileItems.contains(where: { $0.url == url }) else { continue }
            paths.insert(IndexPath(indexes: [0, i]))
        }
        return paths
    }

    fileprivate func canWriteFileItems(at indexPaths: Set<IndexPath>, to pasteboard: NSPasteboard) -> Bool {
        let fileItems = self.fileItems(at: indexPaths)
        return !fileItems.isEmpty && !fileItems.contains { $0.isBusy }
    }
    
    fileprivate func canReadFileItems(from pasteboard: NSPasteboard) -> Bool {
        let urls: [NSURL] = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] ?? []
        return urls.contains { self.fileSystem.canCopy($0 as URL, to: ($0 as URL).movedTo(self.url)) }
    }
    
    @discardableResult fileprivate func deleteFiles<T: Collection>(_ fileItems: T) -> [FileOperation] where T.Iterator.Element == FileItem {
        assert(!fileItems.contains(where: { $0.isBusy }), "Can not delete busy files.")
        
        let validFileItems = fileItems.filter { !$0.isBusy }
        let fileOperations = validFileItems.map { fileItem -> FileOperation in
            
            self.setBusyUrl(fileItem.url)
            return self.fileSystem.delete(fileItem.url)
            
        }
        
        let completionOperations = fileOperations.map { fileOperation -> Operation in
            let operation = BlockOperation {
                
                guard let srcUrl = fileOperation.source else { assertionFailure("Expected non-nil source for delete operation (\(fileOperation))."); return }
                
                let succeeded = !fileOperation.isCancelled && fileOperation.error == nil
                if succeeded {
                    self.removeFileItem(withURL: srcUrl)
                }
                else {
                    self.resetBusyUrl(srcUrl)
                }
                
            }
            operation.addDependency(fileOperation)
            return operation
        }
        
        let finalCompletionOperation = BlockOperation {
            
            self.handleErrors(for: fileOperations)
            self.removeDeletedItems()
            self.updateStatusInfo()
            DispatchQueue.main.async { self.updateProgress() }
            
        }
        for op in completionOperations { finalCompletionOperation.addDependency(op) }
        
        self.fileOperationsQueue.addOperations(completionOperations + [finalCompletionOperation], waitUntilFinished: false)
        updateProgress()
        
        return fileOperations
    }
    
    @discardableResult fileprivate func copyFiles<T: Collection>(_ fileItems: T, to: URL) -> [FileOperation] where T.Iterator.Element == FileItem {
        assert(!fileItems.contains(where: { $0.isBusy }), "Can not copy busy files.")
        assert(fileSystem.isUnderRoot(to) || !fileItems.contains(where: { !fileSystem.isUnderRoot($0.url) }), "Copy sources or destination must be on current file system.")
        
        let validFileItems = fileItems.filter { !$0.isBusy }
        let fileOperations = validFileItems.map { fileItem -> FileOperation in
            
            let destUrl = fileItem.url.movedTo(to)
            //self.setBusyUrl(fileItem.url, isNew: false)
            //self.setBusyUrl(destUrl, isNew: true)
            return self.fileSystem.copy(fileItem.url, to: destUrl)
            
        }
        
        let completionOperations = fileOperations.map { fileOperation -> Operation in
            let operation = BlockOperation {
                
                //guard let srcUrl = fileOperation.source else { assertionFailure("Expected non-nil source for copy operation (\(fileOperation))."); return }
                guard let destUrl = fileOperation.destination else { assertionFailure("Expected non-nil destination for copy operation (\(fileOperation))."); return }
                
                let succeeded = !fileOperation.isCancelled && fileOperation.error == nil
                //self.resetBusyUrl(srcUrl, isDeleted: false)
                if succeeded {
                    self.resetBusyUrl(destUrl)
                }
                else {
                    self.removeFileItem(withURL: destUrl)
                }
                
            }
            operation.addDependency(fileOperation)
            return operation
        }
        
        let finalCompletionOperation = BlockOperation {
            
            self.handleErrors(for: fileOperations)
            self.removeDeletedItems()
            self.updateStatusInfo()
            DispatchQueue.main.async { self.updateProgress() }
            
        }
        for op in completionOperations { finalCompletionOperation.addDependency(op) }
        
        self.fileOperationsQueue.addOperations(completionOperations + [finalCompletionOperation], waitUntilFinished: false)
        updateProgress()
        
        return fileOperations
    }
    
    @discardableResult fileprivate func moveFiles<T: Collection>(_ fileItems: T, to: URL) -> [FileOperation] where T.Iterator.Element == FileItem {
        assert(!fileItems.contains(where: { $0.isBusy }), "Can not move busy files.")
        assert(!fileItems.contains(where: { !fileSystem.isUnderRoot($0.url) }), "Move sources must be on current file system.")
        assert(fileSystem.isUnderRoot(to), "Move destination must be on current file system.")
        
        let validFileItems = fileItems.filter { !$0.isBusy }
        let fileOperations = validFileItems.map { fileItem -> FileOperation in
            
            let destUrl = fileItem.url.movedTo(to)
            self.setBusyUrl(fileItem.url)
            //self.setBusyUrl(destUrl, isNew: true)
            return self.fileSystem.move(fileItem.url, to: destUrl)
            
        }
        
        let completionOperations = fileOperations.map { fileOperation -> Operation in
            let operation = BlockOperation {
                
                guard let srcUrl = fileOperation.source else { assertionFailure("Expected non-nil source for move operation (\(fileOperation))."); return }
                guard let destUrl = fileOperation.destination else { assertionFailure("Expected non-nil destination for move operation (\(fileOperation))."); return }
                
                let succeeded = !fileOperation.isCancelled && fileOperation.error == nil
                if succeeded {
                    self.removeFileItem(withURL: srcUrl)
                    self.resetBusyUrl(destUrl)
                }
                else {
                    self.resetBusyUrl(srcUrl)
                    self.removeFileItem(withURL: destUrl)
                }
                
            }
            operation.addDependency(fileOperation)
            return operation
        }
        
        let finalCompletionOperation = BlockOperation {
            
            self.handleErrors(for: fileOperations)
            self.removeDeletedItems()
            self.updateStatusInfo()
            DispatchQueue.main.async { self.updateProgress() }
            
        }
        for op in completionOperations { finalCompletionOperation.addDependency(op) }
        
        self.fileOperationsQueue.addOperations(completionOperations + [finalCompletionOperation], waitUntilFinished: false)
        updateProgress()
        
        return fileOperations
    }
    
    @discardableResult fileprivate func renameFile(_ fileItem: FileItem, to: String) -> FileOperation {
        let destUrl = fileItem.url.renamed(to: to)
        assert(fileSystem.canMove(fileItem, to: destUrl), "Can not rename file.")
        
        setBusyUrl(fileItem.url, reload: false)
        let fileOperation = self.fileSystem.move(fileItem.url, to: destUrl)
        
        let completionOperation = BlockOperation {
            
            guard let srcUrl = fileOperation.source else { assertionFailure("Expected non-nil source for rename operation (\(fileOperation))."); return }
            guard let destUrl = fileOperation.destination else { assertionFailure("Expected non-nil destination for rename operation (\(fileOperation))."); return }
            
            let succeeded = !fileOperation.isCancelled && fileOperation.error == nil
            if succeeded {
                if let indexPath = self.indexPath(for: srcUrl), let index = self.items.index(where: { $0.url == srcUrl }) {
                    self.resetBusyUrl(srcUrl, reload: false)
                    let newFileItem = FileItem(url: destUrl)
                    self.items[index] = newFileItem
                    self.itemArrayController.content = self.items
                    if let newIndexPath = self.indexPath(for: newFileItem) {
                        self.collectionView.moveItem(at: indexPath, to: newIndexPath)
                        self.collectionView.reloadItems(at: [newIndexPath])
                    }
                    else {
                        self.removeFileItem(withURL: srcUrl)
                        self.removeDeletedItems()
                    }
                }
                else {
                    self.resetBusyUrl(srcUrl)
                    self.addNewFileItem(withURL: destUrl)
                }
            }
            else {
                self.resetBusyUrl(srcUrl)
            }
            
            self.handleErrors(for: [fileOperation])
            self.updateStatusInfo()
            self.updatePathControl()
            DispatchQueue.main.async { self.updateProgress() }
        }
        completionOperation.addDependency(fileOperation)
        self.fileOperationsQueue.addOperation(completionOperation)
        updateProgress()
        
        return fileOperation
    }
    
    @discardableResult fileprivate func createFolder(_ url: URL) -> FileOperation {
        assert(self.fileSystem.canCreateFolder(url), "File system does not support creating a folder [\(url)].")
        
        let fileOperation = self.fileSystem.createFolder(url)
        
        let completionOperation = BlockOperation {
            
            guard let destUrl = fileOperation.destination else { assertionFailure("Expected non-nil destination for create folder operation (\(fileOperation))."); return }
            
            let succeeded = !fileOperation.isCancelled && fileOperation.error == nil
            if succeeded {
                self.resetBusyUrl(destUrl)
                self.startEditing(destUrl)
            }
            else {
                self.removeFileItem(withURL: destUrl)
                self.removeDeletedItems()
            }
            
            self.handleErrors(for: [fileOperation])
            self.updateStatusInfo()
            DispatchQueue.main.async { self.updateProgress() }
            
        }
        completionOperation.addDependency(fileOperation)
        self.fileOperationsQueue.addOperation(completionOperation)
        updateProgress()
        
        return fileOperation
    }
    
    @discardableResult fileprivate func openFile(_ fileItem: FileItem) -> FileOperation {
        assert(self.fileSystem.canOpenFile(fileItem), "File system does not support opening a file [\(url)].")
        
        guard let copyOperation = copyFiles([fileItem], to: self.fileSystem.tempDownloadsDirectory).first else { assertionFailure("Expected to get one copy operation."); return FileOperation(operation: .copy, source: fileItem.url, error: FileSystemError.internalFailure) }
        
        let loadingController = LoadingWindowController.loadController()
        loadingController.titleLabel.stringValue = String(format: NSLocalizedString("Opening file %@", comment: ""), fileItem.name)
        loadingController.hintLabel.stringValue = NSLocalizedString("Cancel opening", comment: "")
        loadingController.dismissHandler = { _ in copyOperation.cancel() }
        loadingController.showWindow(self)
        
        let completionOperation = BlockOperation {
            loadingController.dismissController(nil)
            DispatchQueue.main.async { self.updateProgress() }
            
            guard !copyOperation.isCancelled else { return }
            guard let destUrl = copyOperation.destination else { assertionFailure("Expected non-nil destination for rename operation (\(copyOperation))."); return }
            guard destUrl.isFileURL else { assertionFailure("Destination URL (\(destUrl)) expected to be a local file."); return }
            guard !destUrl.hasDirectoryPath else { assertionFailure("Destination URL (\(destUrl)) expected to be a simple file."); return }
            NSWorkspace.shared.openFile(destUrl.path)
        }
        completionOperation.addDependency(copyOperation)
        OperationQueue.main.addOperation(completionOperation)
        updateProgress()
        
        return copyOperation
    }

    
    /// Remove busy mark from url, mark it as deleted or restore to normal
    fileprivate func resetBusyUrl(_ url: URL, reload: Bool = true) {
        self.busyURLs.remove(url)
        
        if let fileItem = self.items.first(where: { $0.url == url }) {
            fileItem.dynamicFlags.remove(.isBusy)
            if let indexPath = self.indexPath(for: fileItem), reload {
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
    }
    
    /// Mark url and correspinding fileItem (if present) as busy
    fileprivate func setBusyUrl(_ url: URL, reload: Bool = true) {
        self.busyURLs.insert(url)
        
        if let fileItem = self.items.first(where: { $0.url == url }) {
            fileItem.dynamicFlags.insert(.isBusy)
            if let indexPath = indexPath(for: fileItem), reload {
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
    }
    
    /// Insert new fileItem if absent reseting busy status
    fileprivate func addNewFileItem(withURL url: URL, reload: Bool = true) {
        self.busyURLs.remove(url)
        
        guard self.url == url.deletingLastPathComponent() else { return }
        if let fileItem = self.items.first(where: { $0.url == url }) {
            fileItem.dynamicFlags = []
            if let indexPath = indexPath(for: fileItem), reload {
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
        else {
            let fileItem = FileItem(url: url)
            self.items.append(fileItem)
            self.itemArrayController.content = self.items
            if let indexPath = indexPath(for: fileItem) {
                self.collectionView.insertItems(at: [indexPath])
            }
        }
    }
    
    /// Mark existing file item as deleted reseting buy status
    fileprivate func removeFileItem(withURL url: URL, reload: Bool = true) {
        self.busyURLs.remove(url)
        
        if let fileItem = self.items.first(where: { $0.url == url }) {
            fileItem.dynamicFlags = [ .isDeleted ]
            if let indexPath = indexPath(for: fileItem), reload {
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
    }
    
    /// Remove items that are marked as deleted
    private func removeDeletedItems() {
        // To avoid full reload of collection view, find positions of deleted items and remove only those items
        var viewIndices: Set<IndexPath> = []
        let arrangedItems: [FileItem] = (self.itemArrayController.arrangedObjects as? [FileItem]) ?? []
        for i in 0 ..< arrangedItems.count {
            guard arrangedItems[i].flags.contains(.isDeleted) else { continue }
            viewIndices.insert(IndexPath(indexes: [0, i]))
        }
        
        // Update data source
        let filteredItems = self.items.filter { !$0.flags.contains(.isDeleted) }
        self.items = filteredItems
        
        // Deleting from collection view must be performed after data source is updated
        self.collectionView.deleteItems(at: viewIndices)
    }
    
    private func handleErrors(for fileOperations: [FileOperation]) {
        let failedOperations = fileOperations.filter { $0.error != nil && !$0.isCancelled }
        guard !failedOperations.isEmpty else { return }
        
        var deleteMessages: [String] = []
        var copyMessages: [String] = []
        var moveMessages: [String] = []
        var createFolderMessages: [String] = []
        for operation in failedOperations {
            guard let error = operation.error else { continue }
            
            switch operation.operation {
            case .delete:
                guard let srcUrl = operation.source else { continue }
                Log.error?.message("Failed to delete file at [\(srcUrl)]: \(error)")
                deleteMessages.append(self.fileSystem.description(for: srcUrl))
            case .copy:
                guard let srcUrl = operation.source else { continue }
                guard let destUrl = operation.destination else { continue }
                Log.error?.message("Failed to copy file from [\(srcUrl)] to [\(destUrl)]: \(error)")
                let srcName = self.fileSystem.description(for: srcUrl)
                let destName = self.fileSystem.description(for: destUrl)
                copyMessages.append(String(format: NSLocalizedString("from %@ to %@", comment: ""), srcName, destName))
            case .move:
                guard let srcUrl = operation.source else { continue }
                guard let destUrl = operation.destination else { continue }
                Log.error?.message("Failed to move file from [\(srcUrl)] to [\(destUrl)]: \(error)")
                let srcName = self.fileSystem.description(for: srcUrl)
                let destName = self.fileSystem.description(for: destUrl)
                moveMessages.append(String(format: NSLocalizedString("from %@ to %@", comment: ""), srcName, destName))
            case .createFolder:
                guard let destUrl = operation.destination else { continue }
                Log.error?.message("Failed to create folder at [\(destUrl)]: \(error)")
                createFolderMessages.append(self.fileSystem.description(for: destUrl))
            }
        }
        
        var text = ""
        if !deleteMessages.isEmpty {
            text += NSLocalizedString("Failed to delete", comment: "") + ":\n\t" + deleteMessages.joined(separator: "\n\t") + "\n"
        }
        if !copyMessages.isEmpty {
            text += NSLocalizedString("Failed to copy", comment: "") + ":\n\t" + copyMessages.joined(separator: "\n\t") + "\n"
        }
        if !moveMessages.isEmpty {
            text += NSLocalizedString("Failed to move", comment: "") + ":\n\t" + moveMessages.joined(separator: "\n\t") + "\n"
        }
        if !createFolderMessages.isEmpty {
            text += NSLocalizedString("Failed to create folder", comment: "") + ":\n\t" + createFolderMessages.joined(separator: "\n\t") + "\n"
        }
        
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Failed to perform file operations", comment: "")
        alert.informativeText = text
        alert.runModal()
    }
    
    private func startEditing(_ url: URL) {
        guard let indexPath = indexPath(for: url) else { return }
        guard let item = self.collectionView.item(at: indexPath) as? IconItem else { return }
        guard let fileItem = item.fileItem else { return }
        guard fileItem.canModify == true else { return }
        self.collectionView.deselectAll(nil)
        self.collectionView.selectItems(at: [indexPath], scrollPosition: .bottom)
        item.startEditing()
    }
    
    fileprivate func writeFileItems(at indexPaths: Set<IndexPath>, to pasteboard: NSPasteboard) -> Bool {
        guard canWriteFileItems(at: indexPaths, to: pasteboard) else { return false }
        let fileItems = self.fileItems(at: indexPaths)
        pasteboard.clearContents()
        pasteboard.writeObjects(fileItems)
        return true
    }
    
    fileprivate func pasteFileItems(from pasteboard: NSPasteboard) -> Bool {
        guard let fileItems: [FileItem] = pasteboard.readObjects(forClasses: [FileItem.self], options: nil) as? [FileItem] else { return false }
        let copyableItems = fileItems.filter { self.fileSystem.canCopy($0, to: $0.url.movedTo(self.url)) }
        guard !copyableItems.isEmpty else { return false }
        copyFiles(copyableItems, to: self.url)
        return true
    }
    
    fileprivate var canOpen: Bool {
        guard self.collectionView.selectionIndexPaths.count == 1 else { return false }
        guard let indexPath = self.collectionView.selectionIndexPaths.first else { return false }
        guard let fileItem = fileItem(at: indexPath) else { return false }
        return canOpen(fileItem)
    }
    
    fileprivate func canOpen(_ fileItem: FileItem) -> Bool {
        return !fileItem.isBusy
    }
    
    fileprivate func open(_ fileItem: FileItem) {
        guard canOpen(fileItem) else { return }
        if fileItem.isDirectory {
            goTo(fileItem.url)
        }
        else if self.fileSystem.canOpenFile(fileItem) {
            openFile(fileItem)
        }
    }
    
    
    // MARK: Actions
    
    @objc func collectionItemViewLabelClick(_ sender: NSCollectionViewItem) {
        guard let item = sender as? IconItem else { return }
        guard self.collectionView.selectionIndexes.count == 1 else { return }
        guard let selectedIndexPath = self.collectionView.selectionIndexPaths.first else { return }
        guard self.collectionView.item(at: selectedIndexPath) == item else { return }
        guard let fileItem = item.fileItem else { return }
        guard fileItem.canModify else { return }
        item.startEditing()
    }
    
    @objc func collectionItemViewDoubleClick(_ sender: NSCollectionViewItem) {
        guard let fileItem = (sender as? IconItem)?.fileItem else { return }
        open(fileItem)
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
    
    @IBAction func toggleHiddenFiles(_ sender: Any?) {
        self.isHiddenFilesVisible = !self.isHiddenFilesVisible
    }
    
    @IBAction func toggleFoldersAlwaysFirst(_ sender: Any?) {
        self.isFoldersAlwaysFirst = !self.isFoldersAlwaysFirst
    }
    
    @IBAction func deleteSelectedFiles(_ sender: Any?) {
        let fileItems: [FileItem] = self.collectionView.selectionIndexPaths.flatMap { fileItem(at: $0) }
        deleteFiles(fileItems)
    }
    
    @IBAction func createFolder(_ sender: Any?) {
        let defaultName = NSLocalizedString("New Folder", comment: "New folder name")
        let url = self.url.appendingPathComponent(defaultName, isDirectory: true)
        let nonExistingUrl = url.nonExisting { url in
            return !self.items.contains(where: { $0.url == url })
        }
        createFolder(nonExistingUrl)
    }
    
    @IBAction func changeIconSize(_ sender: NSSlider?) {
        guard let slider = sender else { assertionFailure("Sender expected to be a valid NSSlider view."); return }
        self.iconsSize = slider.integerValue
    }
    
    @IBAction func goBackForward(_ sender: NSSegmentedControl?) {
        guard let control = sender else { assertionFailure("Sender expected to be a valid NSSegmentedControl view."); return }
        switch control.selectedSegment {
        case 0: goBack(nil)
        case 1: goForward(nil)
        default: return
        }
    }
    
    @IBAction func pathControlDoubleClicked(_ sender: NSPathControl?) {
        guard let control = sender else { assertionFailure("Sender expected to be a valid NSPathControl view."); return }
        guard let url = control.clickedPathItem?.url else { return }
        self.goTo(url)
    }
    
    @IBAction func copy(_ sender: Any?) {
        if !self.writeFileItems(at: self.collectionView.selectionIndexPaths, to: NSPasteboard.general) {
            NSSound.beep()
        }
    }
    
    @IBAction func paste(_ sender: Any?) {
        if !self.pasteFileItems(from: NSPasteboard.general) {
            NSSound.beep()
        }
    }
    
    @IBAction func open(_ sender: Any?) {
        guard self.canOpen else { return }
        guard let indexPath = self.collectionView.selectionIndexPaths.first else { return }
        guard let fileItem = fileItem(at: indexPath) else { return }
        open(fileItem)
    }
    
    
    // MARK: Menu / Toolbar
    
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.tag {
        case AppDelegate.MenuItemTags.back: return self.canGoBack
        case AppDelegate.MenuItemTags.forward: return self.canGoForward
        case AppDelegate.MenuItemTags.enclosingFolder: return self.canGoUp
        case AppDelegate.MenuItemTags.toggleHiddenFiles:
            menuItem.title = self.isHiddenFilesVisible ? NSLocalizedString("Hide Hidden Files", comment: "") : NSLocalizedString("Show Hidden Files", comment: "")
            return true
        case AppDelegate.MenuItemTags.foldersAlwaysFirst:
            menuItem.state = self.isFoldersAlwaysFirst ? NSControl.StateValue.on : NSControl.StateValue.off
            return true
        case AppDelegate.MenuItemTags.deleteFiles: return !self.collectionView.selectionIndexPaths.isEmpty
        case AppDelegate.MenuItemTags.newFolder: return true
        case AppDelegate.MenuItemTags.open: return self.canOpen
        default: break
        }
        
        guard let action = menuItem.action else { return super.validateMenuItem(menuItem) }
        switch action {
        case #selector(copy(_:)): return self.canWriteFileItems(at: self.collectionView.selectionIndexPaths, to: NSPasteboard.general)
        case #selector(paste(_:)): return self.canReadFileItems(from: NSPasteboard.general)
        default: return super.validateMenuItem(menuItem)
        }
    }
    
    override func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.tag {
        case AppDelegate.ToolbarItemTags.backForward:
            guard let view = item.view as? NSSegmentedControl else { return false }
            view.setEnabled(self.canGoBack, forSegment: 0)
            view.setEnabled(self.canGoForward, forSegment: 1)
            return true
        default: return false
        }
    }
}


// MARK: NSWindowDelegate

extension BrowserWindowController: NSWindowDelegate {
    
    func windowWillClose(_ notification: Notification) {
        self.delegate?.browserWindowWillClose(self)
    }
    
}


// MARK: NSCollectionViewDataSource

extension BrowserWindowController : NSCollectionViewDataSource {
    
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.arrangedItems.count
    }
    
    func collectionView(_ itemForRepresentedObjectAtcollectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "IconItem"), for: indexPath)
        guard let iconItem = item as? IconItem else { return item }
        
        let fileItems = self.arrangedItems
        guard fileItems.count > indexPath.item else { assertionFailure("indexPath.item (\(indexPath.item)) out of arrangedItems bounds (0..<\(fileItems.count))."); return item }
        
        iconItem.fileItem = fileItems[indexPath.item]
        iconItem.delegate = self
        
        return item
    }
    
}


// MARK: NSCollectionViewDelegate

extension BrowserWindowController: NSCollectionViewDelegate {
    
    /* This method is called after it has been determined that a drag should begin, but before the drag has been started. To refuse the drag, return NO. To start the drag, declare the pasteboard types that you support with -[NSPasteboard declareTypes:owner:], place your data for the items at the given index paths on the pasteboard, and return YES from the method. The drag image and other drag related information will be set up and provided by the view once this call returns YES. You need to implement this method, or -collectionView:pasteboardWriterForItemAtIndexPath:, for your collection view to be a drag source.
     */
    public func collectionView(_ collectionView: NSCollectionView, writeItemsAt indexPaths: Set<IndexPath>, to pasteboard: NSPasteboard) -> Bool {
        return writeFileItems(at: indexPaths, to: pasteboard)
    }
    
    
    /* The delegate can support file promise drags by adding NSFilesPromisePboardType to the pasteboard in -collectionView:writeItemsAtIndexPaths:toPasteboard:. NSCollectionView implements -namesOfPromisedFilesDroppedAtDestination: to return the results of this delegate method. This method should return an array of filenames (not full paths) for the created files. The URL represents the drop location. For more information on file promise dragging, see documentation for the NSDraggingSource protocol and -namesOfPromisedFilesDroppedAtDestination:. You do not need to implement this method for your collection view to be a drag source.
     */
    public func collectionView(_ collectionView: NSCollectionView, namesOfPromisedFilesDroppedAtDestination dropURL: URL, forDraggedItemsAt indexPaths: Set<IndexPath>) -> [String] {
        let fileItems = self.fileItems(at: indexPaths)
        guard fileItems.count > 0 else { return [] }
        guard dropURL.isFileURL else { return [] }
        
        let operations = copyFiles(fileItems, to: dropURL)
        
        return operations.flatMap { return $0.destination?.lastPathComponent }
    }
    
    
    /* Allows the delegate to construct a custom dragging image for the items being dragged. 'indexPaths' contains the (section,item) identification of the items being dragged. 'event' is a reference to the  mouse down event that began the drag. 'dragImageOffset' is an in/out parameter. This method will be called with dragImageOffset set to NSZeroPoint, but it can be modified to re-position the returned image. A dragImageOffset of NSZeroPoint will cause the image to be centered under the mouse. You can safely call -[NSCollectionView draggingImageForItemsAtIndexPaths:withEvent:offset:] from within this method. You do not need to implement this method for your collection view to be a drag source.
     */
//    optional public func collectionView(_ collectionView: NSCollectionView, draggingImageForItemsAt indexPaths: Set<IndexPath>, with event: NSEvent, offset dragImageOffset: NSPointPointer) -> NSImage
    
    public func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        
        let pasteboard = draggingInfo.draggingPasteboard()
        
        // Basic check if there is interesting content
        guard pasteboard.availableType(from: type(of: self).dropTypes) != nil else { return [] }
        
        // Drop either into folder or at the end of the list
        let allItems = self.arrangedItems
        if proposedDropOperation.pointee == .on && proposedDropIndexPath.pointee.item < allItems.count {
            guard let item = fileItem(at: proposedDropIndexPath.pointee as IndexPath) else { return [] }
            if !item.isDirectory {
                proposedDropIndexPath.pointee = NSIndexPath(forItem: allItems.count, inSection: 0)
                proposedDropOperation.pointee = .before
            }
        }
        else {
            proposedDropIndexPath.pointee = NSIndexPath(forItem: allItems.count, inSection: 0)
            proposedDropOperation.pointee = .before
        }
        
        // Get drop target url
        var destUrl = self.url
        if proposedDropOperation.pointee == .on {
            guard let item = fileItem(at: proposedDropIndexPath.pointee as IndexPath) else { assertionFailure("Cant accept pasteboard items - drop index path is invalid."); return [] }
            guard item.isDirectory else { assertionFailure("Cant accept pasteboard items - drop target expecte dto be a directory."); return [] }
            destUrl = item.url
        }
        
        // Count valid items
        let urls: [NSURL] = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] ?? []
        let copyableUrls = urls.filter { self.fileSystem.canCopy($0 as URL, to: ($0 as URL).movedTo(destUrl)) }
        let movableUrls = urls.filter { self.fileSystem.canCopy($0 as URL, to: ($0 as URL).movedTo(destUrl)) }
        
        guard !copyableUrls.isEmpty || !movableUrls.isEmpty else { return [] }
        
        let validItemCount: Int
        let operation: NSDragOperation
        if (!movableUrls.isEmpty && !NSEvent.modifierFlags.contains(.option)) || copyableUrls.isEmpty {
            operation =  [ .move ]
            validItemCount = movableUrls.count
        }
        else {
            operation =  [ .copy ]
            validItemCount = copyableUrls.count
        }
        
        draggingInfo.draggingFormation = .stack
        draggingInfo.animatesToDestination = false
        if draggingInfo.numberOfValidItemsForDrop != validItemCount {
            // Set only if different to avoid flickering of drag image
            draggingInfo.numberOfValidItemsForDrop = validItemCount
        }
        
        return operation
    }
    
    
    /* This method is called when the mouse is released over a collection view that previously decided to allow a drop via the above validateDrop method. At this time, the delegate should incorporate the data from the dragging pasteboard and update the collection view's contents. You must implement this method for your collection view to be a drag destination.
     
     Multi-image drag and drop: If draggingInfo.animatesToDestination is set to YES, you should enumerate and update the dragging items with the proper image components and frames so that they dragged images animate to the proper locations.
     */
    public func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        
        let pasteboard = draggingInfo.draggingPasteboard()
        
        // Basic check if there is interesting content
        guard pasteboard.availableType(from: type(of: self).dropTypes) != nil else { assertionFailure("Cant accept pasteboard items - no supported drop types"); return false }
        
        // Drop either into folder or at the end of the list
        var destUrl = self.url
        if dropOperation == .on {
            guard let item = fileItem(at: indexPath) else { assertionFailure("Cant accept pasteboard items - drop index path is invalid."); return false }
            guard item.isDirectory else { assertionFailure("Cant accept pasteboard items - drop target expecte dto be a directory."); return false }
            destUrl = item.url
        }
        
        // Gather dropped file items
        guard let fileItems: [FileItem] = pasteboard.readObjects(forClasses: [FileItem.self], options: nil) as? [FileItem] else { return false }
        let copyableItems = fileItems.filter { self.fileSystem.canCopy($0, to: $0.url.movedTo(destUrl)) }
        let movableItems = fileItems.filter { self.fileSystem.canMove($0, to: $0.url.movedTo(destUrl)) }
        
        guard !copyableItems.isEmpty || !movableItems.isEmpty else { return false }
        
        if (!movableItems.isEmpty && !NSEvent.modifierFlags.contains(.option)) || copyableItems.isEmpty {
            moveFiles(movableItems, to: destUrl)
        }
        else {
            copyFiles(copyableItems, to: destUrl)
        }
        
        return true
    }
    
    
    /* Multi-image drag and drop */
    
    /* Dragging Source Support - Required for multi-image drag and drop. Return a custom object that implements NSPasteboardWriting (or simply use NSPasteboardItem), or nil to prevent dragging for the item. For each valid item returned, NSCollectionView will create an NSDraggingItem with the draggingFrame equal to the frame of the item view at the given index path and components from -[NSCollectionViewItem draggingItem]. If this method is implemented, then -collectionView:writeItemsAtIndexPaths:toPasteboard: and -collectionView:draggingImageForItemsAtIndexPaths:withEvent:offset: will not be called.
     */
//    public func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
//        let allFileItems = self.arrangedItems
//        guard indexPath.item < allFileItems.count else { assertionFailure("indexPath.item (\(indexPath.item)) out of arrangedItems bounds (0..<\(allFileItems.count))"); return nil }
//        let fileItem = allFileItems[indexPath.item]
//        return fileItem
//    }
    
    
    /* Dragging Source Support - Optional. Implement this method to know when the dragging session is about to begin and to potentially modify the dragging session.
     */
//    public func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) 
    
    
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
//    public func collectionView(_ collectionView: NSCollectionView, shouldChangeItemsAt indexPaths: Set<IndexPath>, to highlightState: NSCollectionViewItemHighlightState) -> Set<IndexPath> {
//        
//        return indexPaths
//    }
    
    
    /* Sent during interactive selection or dragging, to inform the delegate that the CollectionView has changed the "highlightState" property of the items at the specified "indexPaths" to the specified "highlightState". */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, didChangeItemsAt indexPaths: Set<IndexPath>, to highlightState: NSCollectionViewItemHighlightState)
    
    
    /* Sent during interactive selection, to inform the delegate that the CollectionView would like to select the items at the specified "indexPaths".  In addition to optionally reacting to the proposed change, you can approve it (by returning "indexPaths" as-is), or selectively refuse some or all of the proposed selection changes (by returning a modified autoreleased mutableCopy of indexPaths, or an empty indexPaths instance).
     */
    public func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        let filtered = indexPaths.filter {
            guard let fileItem = self.fileItem(at: $0) else { return false }
            return !fileItem.isBusy && !fileItem.isDeleted
        }
        return Set<IndexPath>(filtered)
    }
    
    
    /* Sent during interactive selection, to inform the delegate that the CollectionView would like to de-select the items at the specified "indexPaths".  In addition to optionally reacting to the proposed change, you can approve it (by returning "indexPaths" as-is), or selectively refuse some or all of the proposed selection changes (by returning a modified autoreleased mutableCopy of indexPaths, or an empty indexPaths instance). */
//    @available(OSX 10.11, *)
//    optional public func collectionView(_ collectionView: NSCollectionView, shouldDeselectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath>
    
    
    /* Sent at the end of interactive selection, to inform the delegate that the CollectionView has selected the items at the specified "indexPaths".
     */
    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        updateStatusInfo()
        updatePathControl()
    }
    
    
    /* Sent at the end of interactive selection, to inform the delegate that the CollectionView has de-selected the items at the specified "indexPaths".
     */
    public func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        updateStatusInfo()
        updatePathControl()
    }
    
    
    
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


// MARK: IconItemDelegate

extension BrowserWindowController: IconItemDelegate {
    
    func iconItem(_ iconItem: IconItem, didChangeName name: String) {
        guard let fileItem = iconItem.fileItem else { return }
        renameFile(fileItem, to: name)
    }
    
}


// MARK: FileSystemDelegate

extension BrowserWindowController: FileSystemDelegate {
    
    func fileSystem(_ fileSystem: FileSystem, willAddFileAt url: URL, from fileOperation: FileOperation) {
        // Dont do anything if renaming
        guard !(fileOperation.operation == .move && fileOperation.source?.deletingLastPathComponent() == fileOperation.destination?.deletingLastPathComponent()) else { return }
        
        addNewFileItem(withURL: url, reload: false)
        setBusyUrl(url)
    }
    
    func fileSystem(_ fileSystem: FileSystem, didAddFileAt url: URL, from fileOperation: FileOperation) {}
    
    func fileSystem(_ fileSystem: FileSystem, didRemoveFileAt url: URL, from fileOperation: FileOperation) {}
    
}
