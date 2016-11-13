//
//  CertificateUtils.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-10-30.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public class CertificateUtils {
    
    public enum CertificateError: Error {
        case getOrCreateIdentityFailure(error: NSError?)
        case deleteIdentityFailure(status: OSStatus)
        case findCertificateFailed(status: OSStatus)
        case createCertificateFailure(error: NSError?)
        case addCertificateFailure(error: NSError?)
        case deleteCertificateFailure(status: OSStatus)
        case findKeyFailure(status: OSStatus)
        case deleteKeyFailure(status: OSStatus)
        case deleteItemFailure(status: OSStatus)
    }
    
    
    // MARK: Identity functions
    
    public class func findValidIdentity(_ name: String) -> SecIdentity? {
        if let identity = findIdentity(name) {
            var certificate: SecCertificate?
            if SecIdentityCopyCertificate(identity, &certificate) == noErr {
                if validate(certificate: certificate!) {
                    return identity
                }
            }
        }
        return nil
    }
    
    public class func findIdentity(_ name: String) -> SecIdentity? {
        return SecIdentityCopyPreferred(name as CFString, nil, nil)
    }
    
    public class func getOrCreateIdentity(_ name: String, expirationInterval: TimeInterval) throws -> SecIdentity {
        var error: NSError? = nil
        if let identity = MYGetOrCreateAnonymousIdentity(name, expirationInterval, &error)?.takeUnretainedValue() {
            return identity
        }
        else {
            throw CertificateError.getOrCreateIdentityFailure(error: error)
        }
    }
    
    public class func deleteIdentity(_ name: String) throws {
        let identityOpt = findIdentity(name)
        
        // remove preferences
        SecIdentitySetPreferred(nil, name as CFString, nil)
        SecCertificateSetPreferred(nil, name as CFString, nil)
        
        guard let identity = identityOpt else { return }
        
        // remove identity itself
        try deleteItem(identity, secClass: kSecClassIdentity)
    }
    
    
    // MARK: Certificate functions
    
    public class func addCertificate(_ certificate: SecCertificate, name: String) throws {
        let attrs: [String: AnyObject] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate
        ]
        var status = SecItemAdd(attrs as CFDictionary, nil)
        if status != noErr {
            throw CertificateError.addCertificateFailure(error: NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil))
        }
        
        status = SecCertificateSetPreferred(certificate, name as CFString, nil)
        if status != noErr {
            try? deleteCertificate(certificate)
            throw CertificateError.addCertificateFailure(error: NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil))
        }
    }
    
    public class func findCertificate(_ name: String) -> SecCertificate? {
        return SecCertificateCopyPreferred(name as CFString, nil)
    }
    
    public class func updateCertificate(_ certificate: SecCertificate?, name: String) throws {
        try deleteCertificate(name)
        if let cert = certificate {
            try addCertificate(cert, name: name)
        }
    }
    
    private class func deleteCertificate(_ certificate: SecCertificate) throws {
        try deleteItem(certificate, secClass: kSecClassCertificate)
    }
    
    public class func deleteCertificate(_ name: String) throws {
        let certificateOpt = findCertificate(name)
        
        // remove preference
        SecCertificateSetPreferred(nil, name as CFString, nil)
        
        guard let certificate = certificateOpt else { return }
        
        // remove certificate itself
        try deleteCertificate(certificate)
    }
    
    public class func compareCertificates(_ certificate1: SecCertificate, _ certificate2: SecCertificate) -> Bool {
        let data1 = SecCertificateCopyData(certificate1) as Data
        let data2 = SecCertificateCopyData(certificate2) as Data
        return data1.elementsEqual(data2)
    }
    
    public class func digest(for certificate: SecCertificate) -> [UInt8] {
        let data = SecCertificateCopyData(certificate) as Data
        var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0, CC_LONG(data.count), &digest)
        }
        return digest
    }
    
    public class func digestString(for certificate: SecCertificate) -> String {
        let digest = self.digest(for: certificate)
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
    
    public class func validate(certificate: SecCertificate) -> Bool {
        let oids: [CFString] = [
            kSecOIDX509V1ValidityNotAfter,
            kSecOIDX509V1ValidityNotBefore,
            kSecOIDCommonName
        ]
        let values = SecCertificateCopyValues(certificate, oids as CFArray?, nil) as? [String:[String:AnyObject]]
        return relativeTime(forOID: kSecOIDX509V1ValidityNotAfter, values: values) >= 0.0
            && relativeTime(forOID: kSecOIDX509V1ValidityNotBefore, values: values) <= 0.0
    }
    
    
    // MARK: Key functions
    
    public class func findKey(_ name: String) throws -> SecKey? {
        let query: [String: AnyObject] = [
            kSecClass as String: kSecClassKey,
            kSecReturnRef as String: kCFBooleanTrue,
            kSecAttrLabel as String: name as AnyObject
        ]
        var keyItem: CFTypeRef? = nil
        let status = SecItemCopyMatching(query as CFDictionary, &keyItem)
        if status == errSecSuccess {
            return (keyItem as! SecKey)
        }
        else if status == errSecItemNotFound {
            return nil
        }
        else {
            throw CertificateError.findKeyFailure(status: status)
        }
    }
    
    @available(OSX 10.12, *)
    public class func deleteKey(_ key: SecKey) throws {
        if let attrs = SecKeyCopyAttributes(key) as? [String:AnyObject] {
            let appLabel = attrs[kSecAttrApplicationLabel as String] as? Data
            let query: [String: AnyObject] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationLabel as String: appLabel as AnyObject
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != noErr && status != errSecItemNotFound {
                throw CertificateError.deleteItemFailure(status: status)
            }
        }
    }
    
    public class func deleteKey(_ name: String) throws {
        try deleteItem(name, secClass: kSecClassKey)
    }
    
    
    
    private class func relativeTime(forOID oid: CFString, values: [String:[String:AnyObject]]?) -> Double {
        guard let dateNumber = values?[oid as String]?[kSecPropertyKeyValue as String] as? NSNumber else { return 0.0 }
        return dateNumber.doubleValue - CFAbsoluteTimeGetCurrent();
    }
    
    private class func deleteItem(_ item: CFTypeRef, secClass: CFString) throws {
        let query: [String: AnyObject] = [
            kSecClass as String: secClass,
            kSecMatchItemList as String: [ item ] as AnyObject
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != noErr && status != errSecItemNotFound {
            throw CertificateError.deleteItemFailure(status: status)
        }
    }
    
    private class func deleteItem(_ name: String, secClass: CFString) throws {
        let query: [String: AnyObject] = [
            kSecClass as String: secClass,
            kSecAttrLabel as String: name as AnyObject
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != noErr && status != errSecItemNotFound {
            throw CertificateError.deleteItemFailure(status: status)
        }
    }
}
