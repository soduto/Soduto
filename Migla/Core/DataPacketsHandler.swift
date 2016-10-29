//
//  DataPacketsHandler.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-09-05.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public protocol DataPacketsHandler {
    
    func handleDataPacket(_ dataPacket:DataPacket, onConnection connection:Connection) -> Bool
    
}
