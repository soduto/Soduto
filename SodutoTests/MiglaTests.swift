//
//  SodutoTests.swift
//  SodutoTests
//
//  Created by Giedrius Stanevičius on 2016-11-01.
//  Copyright © 2016 Soduto. All rights reserved.
//

import XCTest
import Soduto

class SodutoCertificateTests: XCTestCase {
    
    var keychain: SecKeychain?
    var defaultKeychain: SecKeychain?
    let identityName = "com.soduto.testIdentity"
    let certificateName = "com.soduto.testCertfificate"
    let expirationInterval: TimeInterval = 60 * 60 * 24 * 356
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        let path = "\(NSTemporaryDirectory())/com.soduto.test".cString(using: .ascii)!
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
    
    
    
    func testIdentityUseWorkflow() {
        // Create identity
        let identity1 = try! CertificateUtils.getOrCreateIdentity(identityName, expirationInterval: self.expirationInterval)
        
        // Get identity
        let identity2 = try! CertificateUtils.getOrCreateIdentity(identityName, expirationInterval: self.expirationInterval)
        var certificate1: SecCertificate?
        var certificate2: SecCertificate?
        SecIdentityCopyCertificate(identity1, &certificate1)
        SecIdentityCopyCertificate(identity2, &certificate2)
        XCTAssert(CertificateUtils.compareCertificates(certificate1!, certificate2!), "Identity certificates expected to be equal")
        
        // Delete identity
        try! CertificateUtils.deleteIdentity(identityName)
        XCTAssert(CertificateUtils.findIdentity(identityName) == nil, "Identity with preference \(identityName) expected to be deleted")
        XCTAssert(CertificateUtils.findCertificate(identityName) == nil, "Certificates with preference name '\(identityName)' expected to be deleted")
        XCTAssert(try! CertificateUtils.findKey(identityName) == nil, "Keys with name '\(identityName)' expected to be deleted")
    }
    
    func testCertificateUseWorkflow() {
        // create a certificate
        let identity = try! CertificateUtils.getOrCreateIdentity(identityName, expirationInterval: self.expirationInterval)
        var identityCert: SecCertificate? = nil
        let status = SecIdentityCopyCertificate(identity, &identityCert)
        XCTAssert(status == errSecSuccess, "Identity expected to have a certificate")
        let certData = SecCertificateCopyData(identityCert!)
        identityCert = nil
        try! CertificateUtils.deleteIdentity(identityName)
        let certificate1 = SecCertificateCreateWithData(nil, certData)
        
        // Save certificate
        try! CertificateUtils.addCertificate(certificate1!, name: certificateName)
        
        // Search certificate
        let certificate2 = CertificateUtils.findCertificate(certificateName)!
        XCTAssert(CertificateUtils.compareCertificates(certificate1!, certificate2), "Certificates expected to be equal")
        
        // delete certificate
        try! CertificateUtils.deleteCertificate(certificateName)
        XCTAssert(CertificateUtils.findCertificate(certificateName) == nil, "Certificates with preference name '\(certificateName)' expected to be deleted")
        XCTAssert(try! CertificateUtils.findKey(certificateName) == nil, "Keys with name '\(certificateName)' expected to be deleted")
    }
    
    
    
    private func string(forStatus status: OSStatus) -> String {
        var string: CFString? = nil
        SecCopyErrorMessageString(status, &string)
        return (string as? String) ?? "Unknown status"
    }
}
