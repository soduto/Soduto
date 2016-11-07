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
    }
    
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
        let query: [String: AnyObject] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchItemList as String: [AnyObject](arrayLiteral: identity) as AnyObject
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != noErr && deleteStatus != errSecItemNotFound {
            throw CertificateError.deleteIdentityFailure(status: deleteStatus)
        }
    }
    
    public class func createCertificate(name: String, expirationInterval: TimeInterval) throws -> SecCertificate {
        var error: NSError? = nil
        if let certificate = MYCreateAnonymousCertificate(name, expirationInterval, &error)?.takeUnretainedValue() {
            return certificate
        }
        else {
            throw CertificateError.createCertificateFailure(error: error)
        }
    }
    
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
        
//        #if !TARGET_OS_IPHONE
//            // kSecAttrLabel is not settable on Mac OS (it's automatically generated from the principal
//            // name.) Instead we use the "preference" mapping mechanism, which only exists on Mac OS.
//            if (!err)
//            err = SecCertificateSetPreferred(certRef, (__bridge CFStringRef)label, NULL);
//            if (!err) {
//                // Check if this is an identity cert, i.e. we have the corresponding private key.
//                // If so, we'll also set the preference for the resulting SecIdentityRef.
//                SecIdentityRef identRef;
//                if (SecIdentityCreateWithCertificate(NULL,  certRef,  &identRef) == noErr) {
//                    err = SecIdentitySetPreferred(identRef, (__bridge CFStringRef)label, NULL);
//                    CFRelease(identRef);
//                }
//            }
//        #endif
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
    
    /**
     Delete certificate from the key chain. Certificate preferences associated with this certificate are not removed
     */
    private class func deleteCertificate(_ certificate: SecCertificate) throws {
        let query: [String: AnyObject] = [
            kSecClass as String: kSecClassCertificate,
            kSecMatchItemList as String: [AnyObject](arrayLiteral: certificate) as AnyObject
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != noErr && status != errSecItemNotFound {
            throw CertificateError.deleteCertificateFailure(status: status)
        }
    }
    
    /**
     Delete certificate and preference  by name
     */
    public class func deleteCertificate(_ name: String) throws {
        let certificateOpt = findCertificate(name)
        
        // remove preference
        SecCertificateSetPreferred(nil, name as CFString, nil)
        
        guard let certificate = certificateOpt else { return }
        
        // remove certificate itself
        let query: [String: AnyObject] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchItemList as String: [AnyObject](arrayLiteral: certificate) as AnyObject
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != noErr && deleteStatus != errSecItemNotFound {
            throw CertificateError.deleteCertificateFailure(status: deleteStatus)
        }
    }
    
    public class func compareCertificates(_ certificate1: SecCertificate, _ certificate2: SecCertificate) -> Bool {
        let data1 = SecCertificateCopyData(certificate1) as Data
        let data2 = SecCertificateCopyData(certificate2) as Data
        return data1.elementsEqual(data2)
    }
    
    public class func digest(for certificate: SecCertificate) -> Data {
        return MYGetCertificateDigest(certificate) as Data
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
    
    
    
    private class func relativeTime(forOID oid: CFString, values: [String:[String:AnyObject]]?) -> Double {
        guard let dateNumber = values?[oid as String]?[kSecPropertyKeyValue as String] as? NSNumber else { return 0.0 }
        return dateNumber.doubleValue - CFAbsoluteTimeGetCurrent();
    }
    
}
