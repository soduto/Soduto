//
//  MiglaTests.swift
//  MiglaTests
//
//  Created by Giedrius Stanevičius on 2016-11-01.
//  Copyright © 2016 Migla. All rights reserved.
//

import XCTest
import Migla

class MiglaCertificateTests: XCTestCase {
    
    var keychain: SecKeychain?
    var defaultKeychain: SecKeychain?
    let identityName = "com.migla.testIdentity"
    let certificateName = "com.migla.testCertfificate"
    let expirationInterval: TimeInterval = 60 * 60 * 24 * 356
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        let path = "\(NSTemporaryDirectory())/com.migla.test".cString(using: .ascii)!
        let password = "abc".cString(using: .ascii)!
        
        SecKeychainOpen(path, &(self.keychain))
        SecKeychainDelete(self.keychain)
        
        var status = SecKeychainCreate(path, UInt32(password.count), password, false, nil, &(self.keychain))
        guard status == noErr else { fatalError("Could not create temporary keychain: \(string(forStatus:status))") }
        
        status = SecKeychainUnlock(self.keychain, UInt32(password.count), password, true)
        guard status == noErr else { fatalError("Could not unlock temporary keychain: \(string(forStatus:status))") }
        
        status = SecKeychainCopyDefault(&(self.defaultKeychain))
        guard status == noErr else { fatalError("Could not save original default keychain: \(string(forStatus:status))") }
        
        status = SecKeychainSetDefault(self.keychain)
        guard status == noErr else { fatalError("Could not set temporary keychain as default: \(string(forStatus:status))") }
        
    }
    
    override func tearDown() {
        SecKeychainSetDefault(self.defaultKeychain)
//        SecKeychainDelete(self.keychain)
        
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testCreateIdentity() {
        let _ = try! CertificateUtils.getOrCreateIdentity(identityName, expirationInterval: self.expirationInterval)
    }
    
    func testGetIdentity() {
        let identity1 = try! CertificateUtils.getOrCreateIdentity(identityName, expirationInterval: self.expirationInterval)
        let identity2 = try! CertificateUtils.getOrCreateIdentity(identityName, expirationInterval: self.expirationInterval)
        var certificate1: SecCertificate?
        var certificate2: SecCertificate?
        SecIdentityCopyCertificate(identity1, &certificate1)
        SecIdentityCopyCertificate(identity2, &certificate2)
        XCTAssert(CertificateUtils.compareCertificates(certificate1!, certificate2!), "Identity certificates expected to be equal")
    }
    
    func testDeleteIdentity() {
        let identity1 = try! CertificateUtils.getOrCreateIdentity(identityName, expirationInterval: self.expirationInterval)
        try! CertificateUtils.deleteIdentity(identityName)
        let identity2 = try! CertificateUtils.getOrCreateIdentity(identityName, expirationInterval: self.expirationInterval)
        var certificate1: SecCertificate?
        var certificate2: SecCertificate?
        SecIdentityCopyCertificate(identity1, &certificate1)
        SecIdentityCopyCertificate(identity2, &certificate2)
        XCTAssert(!CertificateUtils.compareCertificates(certificate1!, certificate2!), "Identity certificates expected to be different")
    }
    
    func testCertificateSaveWorkflow() {
        let certificate1 = try! CertificateUtils.createCertificate(name: certificateName, expirationInterval: self.expirationInterval)
        
        try! CertificateUtils.addCertificate(certificate1, name: certificateName)
        let certificate2 = CertificateUtils.findCertificate(certificateName)!
        XCTAssert(CertificateUtils.compareCertificates(certificate1, certificate2), "Certificates expected to be equal")
        
        try! CertificateUtils.deleteCertificate(certificateName)
        let certificate3 = CertificateUtils.findCertificate(certificateName)
        XCTAssert(certificate3 == nil, "Certificates expected to be nil")
    }
    
    
    
    private func string(forStatus status: OSStatus) -> String {
        var string: CFString? = nil
        SecCopyErrorMessageString(status, &string)
        return (string as? String) ?? "Unknown status"
    }
}
