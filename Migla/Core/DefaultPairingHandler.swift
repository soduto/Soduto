//
//  DefaultPairingHandler.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-09-05.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public enum PairingHandlerError: Error {
    case AlreadyPaired
    case PairingAlreadyRequested
    case DeclinedByPeer
}

public protocol PairingHandlerDelegate: class {
    
    func send(_ packet: DataPacket)
    
}



/**
 
 Pairing data packet utilities
 
 */
public extension DataPacket {
    
    public static let PairingPacketType = "kdeconnect.pair"
    
    public enum PairingProperty: String {
        case PairFlag = "pair"
    }
    
    public enum PairingError: Error {
        case WrongType
        case InvalidPairFlag
    }
    
    public static func pair() -> DataPacket {
        let body: Body = [
            PairingProperty.PairFlag.rawValue: NSNumber(value: true)
        ]
        let packet = DataPacket(type: PairingPacketType, body: body)
        return packet
    }
    
    public static func unpair() -> DataPacket {
        let body: Body = [
            PairingProperty.PairFlag.rawValue: NSNumber(value: false)
        ]
        let packet = DataPacket(type: PairingPacketType, body: body)
        return packet
    }
    
    public func getPairFlag() throws -> Bool {
        try self.validatePairingType()
        guard let tcpPort = body[PairingProperty.PairFlag.rawValue] as? NSNumber else { throw PairingError.InvalidPairFlag }
        return tcpPort.boolValue
    }
    
    public func validatePairingType() throws {
        guard type == DataPacket.PairingPacketType else { throw PairingError.WrongType }
    }
}



/**
 
 Implement default data packets based pairing functionality
 
 */
public class DefaultPairingHandler: DataPacketsHandler, Pairable {
    
    /** 
     A delegate object providing needed services for this handler (like packets sendings)
     */
    public weak var delegate: PairingHandlerDelegate? = nil
    
    /**
     Identity to be used when calling `pairingDelegate` functions. If nil - self would be used
     */
    public weak var impersonateAs: PairableClass? = nil
    
    
    
    public init(paired: Bool) {
        self.pairingStatus = paired ? .Paired : .Unpaired
    }
    
    
    
    // MARK: DataPacketsHandler
    
    public func handleDataPacket(_ dataPacket:DataPacket, onConnection connection:Connection) -> Bool {
        assert(self.delegate != nil, "Delegate required for \(type(of: self))")
        
        if dataPacket.type == DataPacket.PairingPacketType {
            do {
                let pairFlag = try dataPacket.getPairFlag()
                if pairFlag {
                    switch self.pairingStatus {
                    case .Unpaired:
                        // Peer initiaites pairing
                        self.pairingStatus = .RequestedByPeer
                        let request = PairingRequest(connection: connection)
                        self.pairingDelegate?.pairable(self.impersonateAs ?? self, receivedRequest: request)
                        break
                    case .Requested:
                        // Peer has accepted our invite
                        self.pairingStatus = .Paired
                        break
                    case .Paired:
                        // The peer does not know that we are already paired?
                        self.acceptPairing()
                        break
                    case .RequestedByPeer:
                        // Already waiting for response from pairing delegate
                        break
                    }
                }
                else {
                    if self.pairingStatus == .Requested {
                        self.pairingDelegate?.pairable(self.impersonateAs ?? self, failedWithError: PairingHandlerError.DeclinedByPeer)
                    }
                    self.pairingStatus = .Unpaired
                }
            }
            catch {
                self.pairingDelegate?.pairable(self.impersonateAs ?? self, failedWithError: error)
            }
        }
        else if self.pairingStatus != .Paired {
            // While not paired - accept only identity packets
            // Also notify peer that we are unpaired if this is the case - we may be unpaired offline and peer might not know about it
            if self.pairingStatus == .Unpaired {
                self.delegate!.send(DataPacket.unpair())
            }
            return true
        }
        return false
    }
    
    
    
    // MARK: Pairable
    
    public weak var pairingDelegate: PairableDelegate? = nil
    
    public private(set) var pairingStatus: PairingStatus {
        didSet {
            if self.pairingStatus != oldValue {
                self.pairingDelegate?.pairable(self.impersonateAs ?? self, statusChanged: self.pairingStatus)
            }
        }
    }
    
    public func requestPairing() {
        assert(self.delegate != nil, "Delegate required for \(type(of: self))")
        
        switch self.pairingStatus {
        case .Unpaired:
            self.pairingStatus = .Requested
            self.delegate!.send(DataPacket.pair())
            break
        case .RequestedByPeer:
            self.acceptPairing()
            break
        case .Requested:
            self.pairingDelegate?.pairable(self.impersonateAs ?? self, failedWithError: PairingHandlerError.PairingAlreadyRequested)
            break
        case .Paired:
            self.pairingDelegate?.pairable(self.impersonateAs ?? self, failedWithError: PairingHandlerError.AlreadyPaired)
            break
        }
    }
    
    public func acceptPairing() {
        assert(self.delegate != nil, "Delegate required for \(type(of: self))")
        
        self.pairingStatus = .Paired
        self.delegate?.send(DataPacket.pair())
    }
    
    public func declinePairing() {
        assert(self.delegate != nil, "Delegate required for \(type(of: self))")
        
        self.pairingStatus = .Unpaired
        self.delegate!.send(DataPacket.unpair())
    }
    
    public func unpair() {
        assert(self.delegate != nil, "Delegate required for \(type(of: self))")
        
        self.pairingStatus = .Unpaired
        self.delegate!.send(DataPacket.unpair())
    }
    
    public func updatePairingStatus(globalStatus: PairingStatus) {
        switch globalStatus {
        case .Paired:
            self.pairingStatus = .Paired
            break
        case .Unpaired:
            self.pairingStatus = .Unpaired
        default:
            break
        }
    }
    
}
