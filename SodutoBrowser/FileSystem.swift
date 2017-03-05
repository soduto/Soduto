//
//  FileSystem.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation

enum FileSystemError {
    case invalidUrl(url: URL)
    case loadFailed(url: URL, reason: String)
}

struct Place {
    let name: String
    let url: URL
    init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

protocol FileSystem: class {
    
    var name: String { get }
    var rootUrl: URL { get }
    var places: [Place] { get }
    
    func load(_ url: URL, completionHandler: @escaping ([FileItem]?, Error?)->Void)
    
}

extension FileSystem {
    
    
    var defaultPlace: Place {
        if self.places.count > 0 {
            return self.places[0]
        }
        else {
            return Place(name: NSLocalizedString("Root", comment: "directory"), url: self.rootUrl)
        }
    }
}
