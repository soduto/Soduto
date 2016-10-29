//
//  Pairable.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-09-05.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public enum PairingStatus: Int {
    case Unpaired
    case Requested
    case RequestedByPeer
    case Paired
}

public struct PairingRequest {
    
    let connection: Connection
    
}

public protocol PairableDelegate: class {
    
    func pairable(_ pairable:Pairable, receivedRequest request:PairingRequest)
    func pairable(_ pairable:Pairable, failedWithError error:Error)
    func pairable(_ pairable:Pairable, statusChanged status:PairingStatus)
    
}

public protocol Pairable {
    
    var pairingDelegate: PairableDelegate? { get set }
    var pairingStatus: PairingStatus { get }
    
    func requestPairing()
    func acceptPairing()
    func declinePairing()
    func unpair()
    func updatePairingStatus(globalStatus: PairingStatus)
}

public protocol PairableClass: class, Pairable {
}
