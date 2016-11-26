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
    
    var peerCertificate: SecCertificate? { get }
    
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
    
    public static func pairPacket() -> DataPacket {
        let body: Body = [
            PairingProperty.PairFlag.rawValue: NSNumber(value: true)
        ]
        let packet = DataPacket(type: PairingPacketType, body: body)
        return packet
    }
    
    public static func unpairPacket() -> DataPacket {
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
public class DefaultPairingHandler: ConnectionDataPacketHandler, Pairable {
    
    static let pairingTimoutInterval: TimeInterval = 30.0
    
    
    /** 
     A delegate object providing needed services for this handler (like packets sendings)
     */
    public weak var delegate: PairingHandlerDelegate? = nil
    
    /**
     Identity to be used when calling `pairingDelegate` functions. If nil - self would be used
     */
    public weak var impersonateAs: PairableClass? = nil
    
    private let config: DeviceConfiguration
    private var pairingTimeout: Timer? = nil
    
    
    
    public init(config: DeviceConfiguration) {
        self.config = config
        self.pairingStatus = self.config.isPaired ? .Paired : .Unpaired
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
                        // Peer initiates pairing
                        self.pairingStatus = .RequestedByPeer
                        let request = PairingRequest(connection: connection)
                        self.pairingDelegate?.pairable(self.impersonateAs ?? self, receivedRequest: request)
                        break
                    case .Requested:
                        // Peer has accepted our invite
                        if self.config.certificate == nil {
                            self.config.certificate = self.delegate!.peerCertificate
                        }
                        self.pairingStatus = .Paired
                        if self.pairingStatus != .Paired {
                            // Failed to set pairingStatus - unpair
                            self.delegate?.send(DataPacket.unpairPacket())
                        }
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
                self.delegate!.send(DataPacket.unpairPacket())
            }
            return true
        }
        return false
    }
    
    
    
    // MARK: Pairable
    
    public weak var pairingDelegate: PairableDelegate? = nil
    
    public private(set) var pairingStatus: PairingStatus {
        willSet {
            assert(newValue != .Paired || self.canSetPaired(), "Can't set pairingStatus to .Paired. Should always use trySetPaired method to safely set paierd status")
            
            self.pairingTimeout?.invalidate()
            self.pairingTimeout = nil
        }
        didSet {
            if self.pairingStatus == .Paired && !self.canSetPaired() {
                Swift.print("Can't set pairingStatus to .Paired. Should always use trySetPaired method to")
                self.pairingStatus = .Unpaired
            }
            if self.pairingStatus != oldValue {
                if self.pairingStatus == .Unpaired {
                    self.config.certificate = nil
                }
                if self.pairingStatus == .Requested || self.pairingStatus == .RequestedByPeer {
                    self.pairingTimeout = Timer(timeInterval: DefaultPairingHandler.pairingTimoutInterval, repeats: false, block: { (timer) in
                        // Every change to pairingStatus should invalidate previous timeout, so if we are here, pairingStatus should still be the same
                        assert(self.pairingStatus == .Requested || self.pairingStatus == .RequestedByPeer, "pairingStatus expected to not be changed")
                        self.declinePairing()
                    })
                    RunLoop.current.add(self.pairingTimeout!, forMode: .defaultRunLoopMode)
                }
                self.pairingDelegate?.pairable(self.impersonateAs ?? self, statusChanged: self.pairingStatus)
            }
        }
    }
    
    public func requestPairing() {
        assert(self.delegate != nil, "Delegate required for \(type(of: self))")
        
        switch self.pairingStatus {
        case .Unpaired:
            self.pairingStatus = .Requested
            self.delegate!.send(DataPacket.pairPacket())
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
        
        if self.config.certificate == nil {
            self.config.certificate = self.delegate!.peerCertificate
        }
        
        // We need to send pair packet before setting pairedStatus.
        // Otherwise pairing status notifications might trigger other data packets to be sent and if 
        // such packets are sent befor pairing, they might be discarded or even cause other device to unpair
        if self.canSetPaired() {
            self.delegate?.send(DataPacket.pairPacket())
            self.trySetPaired()
        }
        
        if self.pairingStatus != .Paired {
            self.delegate?.send(DataPacket.unpairPacket())
        }
    }
    
    public func declinePairing() {
        assert(self.delegate != nil, "Delegate required for \(type(of: self))")
        
        self.pairingStatus = .Unpaired
        self.delegate!.send(DataPacket.unpairPacket())
    }
    
    public func unpair() {
        assert(self.delegate != nil, "Delegate required for \(type(of: self))")
        
        self.pairingStatus = .Unpaired
        self.delegate!.send(DataPacket.unpairPacket())
    }
    
    public func updatePairingStatus(globalStatus: PairingStatus) {
        switch globalStatus {
        case .Paired:
            self.trySetPaired()
            break
        case .Unpaired:
            self.pairingStatus = .Unpaired
        default:
            break
        }
    }
    
    
    // MARK: Private methods
    
    private func canSetPaired() -> Bool {
        return self.config.certificate != nil
    }
    
    private func trySetPaired() {
        if self.canSetPaired() {
            self.pairingStatus = .Paired
        }
        else {
            self.pairingStatus = .Unpaired
        }
    }
}
