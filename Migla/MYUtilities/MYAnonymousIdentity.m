//
//  MYAnonymousIdentity.m
//  MYUtilities
//
//  Created by Jens Alfke on 12/5/14.
//

#import "MYAnonymousIdentity.h"
#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>


// Raw data of an anonymous X.509 cert:
static uint8_t const kCertTemplate[499];

// Key size of kCertTemplate:
#define kKeySizeInBits     2048

// These are offsets into kCertTemplate where values need to be substituted:
#define kSerialOffset        15
#define kSerialLength         1
#define kIssueDateOffset     68
#define kExpDateOffset       83
#define kDateLength          13
#define kPublicKeyOffset    155
#define kPublicKeyLength    270u
#define kCSROffset            0
#define kCSRLength          494u
#define kSignatureLength    256u


static BOOL checkErr(OSStatus err, NSError** outError);
static NSData* generateAnonymousCert(SecKeyRef publicKey, SecKeyRef privateKey,
                                     NSTimeInterval expirationInterval,
                                     NSError** outError);
static BOOL checkCertValid(SecCertificateRef cert, NSTimeInterval expirationInterval);
static BOOL generateRSAKeyPair(int sizeInBits,
                               BOOL permanent,
                               NSString* label,
                               SecKeyRef *publicKey,
                               SecKeyRef *privateKey,
                               NSError** outError);
static NSData* getPublicKeyData(SecKeyRef publicKey);
static NSData* signData(SecKeyRef privateKey, NSData* inputData);
static SecCertificateRef addCertToKeychain(NSData* certData, NSString* label,
                                           NSError** outError);
static SecIdentityRef findIdentity(NSString* label, NSTimeInterval expirationInterval);

#if TARGET_OS_IPHONE
static void removePublicKey(SecKeyRef publicKey);
#endif


SecIdentityRef MYGetOrCreateAnonymousIdentity(NSString* label,
                                              NSTimeInterval expirationInterval,
                                              NSError** outError)
{
    NSCParameterAssert(label);
    SecIdentityRef ident = findIdentity(label, expirationInterval);
    if (!ident) {
        Log(@"Generating new anonymous self-signed SSL identity labeled \"%@\"...", label);
        SecKeyRef publicKey, privateKey;
        if (!generateRSAKeyPair(kKeySizeInBits, YES, label, &publicKey, &privateKey, outError))
            return NULL;
        NSData* certData = generateAnonymousCert(publicKey,privateKey, expirationInterval,outError);
        if (!certData)
            return NULL;
        SecCertificateRef certRef = addCertToKeychain(certData, label, outError);
        if (!certRef)
            return NULL;
#if TARGET_OS_IPHONE
        removePublicKey(publicKey); // workaround for Radar 18205627
        ident = findIdentity(label, expirationInterval);
        if (!ident)
            checkErr(errSecItemNotFound, outError);
#else
        if (checkErr(SecIdentityCreateWithCertificate(NULL, certRef, &ident), outError))
            CFAutorelease(ident);
#endif
        if (!ident)
            Warn(@"MYAnonymousIdentity: Crap, can't find the identity I just created!");
    }
    return ident;
}


static BOOL checkErr(OSStatus err, NSError** outError) {
    if (err == noErr)
        return YES;
    NSDictionary* info = nil;
#if !TARGET_OS_IPHONE
    NSString* message = CFBridgingRelease(SecCopyErrorMessageString(err, NULL));
    if (message)
        info = @{NSLocalizedDescriptionKey: $sprintf(@"%@ (%d)", message, (int)err)};
#endif
    if (outError)
        *outError = [NSError errorWithDomain: NSOSStatusErrorDomain code: err userInfo: info];
    return NO;
}


// Generates an RSA key-pair, optionally adding it to the keychain.
static BOOL generateRSAKeyPair(int sizeInBits,
                               BOOL permanent,
                               NSString* label,
                               SecKeyRef *publicKey,
                               SecKeyRef *privateKey,
                               NSError** outError)
{
#if TARGET_OS_IPHONE
    NSDictionary *keyAttrs = @{(__bridge id)kSecAttrIsPermanent: @(permanent),
                               (__bridge id)kSecAttrLabel: label};
#endif
    NSDictionary *pairAttrs = @{(__bridge id)kSecAttrKeyType:       (__bridge id)kSecAttrKeyTypeRSA,
                                (__bridge id)kSecAttrKeySizeInBits: @(sizeInBits),
                                (__bridge id)kSecAttrLabel:         label,
#if TARGET_OS_IPHONE
                                (__bridge id)kSecPublicKeyAttrs:    keyAttrs,
                                (__bridge id)kSecPrivateKeyAttrs:   keyAttrs
#else
                                (__bridge id)kSecAttrIsPermanent:   @(permanent)
#endif
                                };
    if (!checkErr(SecKeyGeneratePair((__bridge CFDictionaryRef)pairAttrs, publicKey, privateKey),
                  outError))
        return NO;
    CFAutorelease(*publicKey);
    CFAutorelease(*privateKey);
    return YES;
}


// Generates a self-signed certificate, returning the cert data.
static NSData* generateAnonymousCert(SecKeyRef publicKey, SecKeyRef privateKey,
                                     NSTimeInterval expirationInterval,
                                     NSError** outError)
{
    // Read the original template certificate file:
    NSMutableData* data = [NSMutableData dataWithBytes: kCertTemplate length: sizeof(kCertTemplate)];
    uint8_t* buf = data.mutableBytes;

    // Write the serial number:
    (void)SecRandomCopyBytes(kSecRandomDefault, kSerialLength, &buf[kSerialOffset]);
    buf[kSerialOffset] &= 0x7F; // non-negative

    // Write the issue and expiration dates:
    NSDateFormatter *x509DateFormatter = [[NSDateFormatter alloc] init];
    x509DateFormatter.dateFormat = @"yyMMddHHmmss'Z'";
    x509DateFormatter.timeZone = [NSTimeZone timeZoneWithName: @"GMT"];
    NSDate* date = [NSDate date];
    const char* dateStr = [[x509DateFormatter stringFromDate: date] UTF8String];
    memcpy(&buf[kIssueDateOffset], dateStr, kDateLength);
    date = [date dateByAddingTimeInterval: expirationInterval];
    dateStr = [[x509DateFormatter stringFromDate: date] UTF8String];
    memcpy(&buf[kExpDateOffset], dateStr, kDateLength);

    // Copy the public key:
    NSData* keyData = getPublicKeyData(publicKey);
    AssertEq(keyData.length, kPublicKeyLength);
    memcpy(&buf[kPublicKeyOffset], keyData.bytes, kPublicKeyLength);

    // Sign the cert:
    NSData* csr = [data subdataWithRange: NSMakeRange(kCSROffset, kCSRLength)];
    NSData* sig = signData(privateKey, csr);
    AssertEq(sig.length, kSignatureLength);
    [data appendData: sig];

    return data;
}


// Returns the data of an RSA public key, in the format used in an X.509 certificate.
static NSData* getPublicKeyData(SecKeyRef publicKey) {
#if TARGET_OS_IPHONE
    NSDictionary *info = @{(__bridge id)kSecValueRef:   (__bridge id)publicKey,
                           (__bridge id)kSecReturnData: @YES};
    CFTypeRef data;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)info, &data) != noErr) {
        Log(@"SecItemCopyMatching failed; input = %@", info);
        return nil;
    }
    Assert(data!=NULL);
    return CFBridgingRelease(data);
#else
    CFDataRef data = NULL;
    if (SecItemExport(publicKey, kSecFormatBSAFE, 0, NULL, &data) != noErr)
        return nil;
    return (NSData*)CFBridgingRelease(data);
#endif
}


#if TARGET_OS_IPHONE
// workaround for Radar 18205627: When iOS reads an identity from the keychain, it may accidentally
// get the public key instead of the private key. The workaround is to remove the public key so
// that only the private one is obtainable. --jpa 6/2015
static void removePublicKey(SecKeyRef publicKey) {
    NSDictionary* query = @{(__bridge id)kSecValueRef: (__bridge id)publicKey};
    OSStatus err = SecItemDelete((__bridge CFDictionaryRef)query);
    if (err)
        Warn(@"Couldn't delete public key: err %d", (int)err);
}
#endif


// Signs a data blob using a private key. Padding is PKCS1 with SHA-1 digest.
static NSData* signData(SecKeyRef privateKey, NSData* inputData) {
#if TARGET_OS_IPHONE
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(inputData.bytes, (CC_LONG)inputData.length, digest);

    size_t sigLen = 1024;
    uint8_t sigBuf[sigLen];
    OSStatus err = SecKeyRawSign(privateKey, kSecPaddingPKCS1SHA1,
                                 digest, sizeof(digest),
                                 sigBuf, &sigLen);
    if(err) {
        Warn(@"SecKeyRawSign failed: %ld", (long)err);
        return nil;
    }
    return [NSData dataWithBytes: sigBuf length: sigLen];

#else
    SecTransformRef transform = SecSignTransformCreate(privateKey, NULL);
    if (!transform)
        return nil;
    NSData* resultData = nil;
    if (SecTransformSetAttribute(transform, kSecDigestTypeAttribute, kSecDigestSHA1, NULL)
        && SecTransformSetAttribute(transform, kSecTransformInputAttributeName,
                                    (__bridge CFDataRef)inputData, NULL)) {
            resultData = CFBridgingRelease(SecTransformExecute(transform, NULL));
        }
    CFRelease(transform);
    return resultData;
#endif
}


// Adds a certificate to the keychain, tagged with a label for future lookup.
static SecCertificateRef addCertToKeychain(NSData* certData, NSString* label,
                                           NSError** outError) {
    SecCertificateRef certRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    if (!certRef) {
        checkErr(errSecIO, outError);
        return NULL;
    }
    CFAutorelease(certRef);
    NSDictionary* attrs = $dict({(__bridge id)kSecClass,     (__bridge id)kSecClassCertificate},
                                {(__bridge id)kSecValueRef,  (__bridge id)certRef},
#if TARGET_OS_IPHONE
                                {(__bridge id)kSecAttrLabel, label}
#endif
                                );
    CFTypeRef result;
    OSStatus err = SecItemAdd((__bridge CFDictionaryRef)attrs, &result);

#if !TARGET_OS_IPHONE
    // kSecAttrLabel is not settable on Mac OS (it's automatically generated from the principal
    // name.) Instead we use the "preference" mapping mechanism, which only exists on Mac OS.
    if (!err)
        err = SecCertificateSetPreferred(certRef, (__bridge CFStringRef)label, NULL);
        if (!err) {
            // Check if this is an identity cert, i.e. we have the corresponding private key.
            // If so, we'll also set the preference for the resulting SecIdentityRef.
            SecIdentityRef identRef;
            if (SecIdentityCreateWithCertificate(NULL,  certRef,  &identRef) == noErr) {
                err = SecIdentitySetPreferred(identRef, (__bridge CFStringRef)label, NULL);
                CFRelease(identRef);
            }
        }
#endif
    checkErr(err, outError);
    return certRef;
}


// Looks up an identity (cert + private key) by the cert's label.
static SecIdentityRef findIdentity(NSString* label, NSTimeInterval expirationInterval) {
    SecIdentityRef identity;
#if TARGET_OS_IPHONE
    NSDictionary* query = @{(__bridge id)kSecClass:     (__bridge id)kSecClassIdentity,
                            (__bridge id)kSecAttrLabel: label,
                            (__bridge id)kSecReturnRef: @YES};
    CFTypeRef ref = NULL;
    OSStatus err = SecItemCopyMatching((__bridge CFDictionaryRef)query, &ref);
    if (err) {
        AssertEq(err, errSecItemNotFound); // other err indicates query dict is malformed
        return NULL;
    }
    identity = (SecIdentityRef)ref;
#else
    identity = SecIdentityCopyPreferred((__bridge CFStringRef)label, NULL, NULL);
#endif

    if (identity) {
        // Check that the cert hasn't expired yet:
        CFAutorelease(identity);
        SecCertificateRef cert;
        if (SecIdentityCopyCertificate(identity, &cert) == noErr) {
            if (!checkCertValid(cert, expirationInterval)) {
                Log(@"SSL identity labeled \"%@\" has expired", label);
                identity = NULL;
                MYDeleteAnonymousIdentity(label);
            }
            CFRelease(cert);
        } else {
            identity = NULL;
        }
    }
    return identity;
}


NSData* MYGetCertificateDigest(SecCertificateRef cert) {
    CFDataRef data = SecCertificateCopyData(cert);
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(CFDataGetBytePtr(data), (CC_LONG)CFDataGetLength(data), digest);
    CFRelease(data);
    return [NSData dataWithBytes: digest length: sizeof(digest)];
}


#if TARGET_OS_IPHONE
static NSDictionary* getItemAttributes(CFTypeRef cert) {
    NSDictionary* query = @{(__bridge id)kSecValueRef: (__bridge id)cert,
                            (__bridge id)kSecReturnAttributes: @YES};
    CFDictionaryRef attrs = NULL;
    OSStatus err = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef*)&attrs);
    if (err) {
        AssertEq(err, errSecItemNotFound);
        return NULL;
    }
    Assert(attrs);
    return CFBridgingRelease(attrs);
}
#endif


#if 0 // Disabling this because I can't find a good way to get a cert's key digest on iOS.
NSData* MYGetCertificatePublicKeyDigest(SecCertificateRef cert) {
#if TARGET_OS_IPHONE
    //FIX: Unfortunately this doesn't work: the SecItem___ API only operates on items that are
    // in the Keychain already, so it fails with errSecItemNotFound on this cert.
    return getItemAttributes(cert)[(__bridge id)kSecAttrPublicKeyHash];
#else
    SecKeyRef publicKey;
    if (SecCertificateCopyPublicKey(cert, &publicKey) != noErr)
        return nil;
    NSData* keyData = getPublicKeyData(publicKey);
    CFRelease(publicKey);
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(keyData.bytes, (CC_LONG)keyData.length, digest);
    return [NSData dataWithBytes: digest length: sizeof(digest)];
#endif
}
#endif // 0


#if !TARGET_OS_IPHONE
static double relativeTimeFromOID(NSDictionary* values, CFTypeRef oid) {
    NSNumber* dateNum = values[(__bridge id)oid][@"value"];
    if (!dateNum)
        return 0.0;
    return dateNum.doubleValue - CFAbsoluteTimeGetCurrent();
}
#endif


// Returns YES if the cert has not yet expired.
static BOOL checkCertValid(SecCertificateRef cert, NSTimeInterval expirationInterval) {
#if TARGET_OS_IPHONE
    NSDictionary* attrs = getItemAttributes(cert);
    // The fucked-up iOS Keychain API doesn't expose the cert expiration date, only the date the
    // item was added to the keychain. So derive it based on the current expiration interval:
    NSDate* creationDate = attrs[(__bridge id)kSecAttrCreationDate];
    return creationDate && -[creationDate timeIntervalSinceNow] < expirationInterval;
#else
    CFArrayRef oids = (__bridge CFArrayRef)@[(__bridge id)kSecOIDX509V1ValidityNotAfter,
                                             (__bridge id)kSecOIDX509V1ValidityNotBefore];
    NSDictionary* values = CFBridgingRelease(SecCertificateCopyValues(cert, oids, NULL));
    return relativeTimeFromOID(values, kSecOIDX509V1ValidityNotAfter) >= 0.0
        && relativeTimeFromOID(values, kSecOIDX509V1ValidityNotBefore) <= 0.0;
#endif
}


BOOL MYDeleteAnonymousIdentity(NSString* label) {
    NSDictionary* attrs = $dict({(__bridge id)kSecClass,     (__bridge id)kSecClassIdentity},
                                {(__bridge id)kSecAttrLabel, label});
    OSStatus err = SecItemDelete((__bridge CFDictionaryRef)attrs);
    if (err != noErr && err != errSecItemNotFound)
        Warn(@"Unexpected error %d deleting identity from keychain", (int)err);
    return (err == noErr);
}




#pragma mark - UNIT TESTS
#if DEBUG

TestCase(GenerateAnonymousCert) {
    static NSString* const kLabel = @"MYAnonymousIdentity unit test";
    SecKeyRef publicKey, privateKey;
    NSError* error;
    Assert(generateRSAKeyPair(kKeySizeInBits, TARGET_OS_IPHONE, kLabel,
                              &publicKey, &privateKey, &error));
    NSData* certData = generateAnonymousCert(publicKey, privateKey, 60*60*24, &error);
    Assert(certData);

    SecCertificateRef certRef;
#if TARGET_OS_IPHONE
    certRef = addCertToKeychain(certData, kLabel, NULL);
#else
    certRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    CFAutorelease(certRef);
#endif
    Assert(certRef);
    Assert(checkCertValid(certRef, 60*60*24));
    [getPublicKeyData(publicKey) writeToFile: @"/tmp/publickey.der" atomically: NO];
    [certData writeToFile: @"/tmp/generated.cer" atomically: NO];

#if TARGET_OS_IPHONE
    NSDictionary* keyAttrs = getItemAttributes(publicKey);
    NSDictionary* certAttrs = getItemAttributes(certRef);
    Log(@"Key attrs = %@", keyAttrs);
    Log(@"Cert attrs = %@", certAttrs);
    AssertEqual(certAttrs[(__bridge id)kSecAttrPublicKeyHash],
                keyAttrs[(__bridge id)kSecAttrApplicationLabel]);
    SecIdentityRef ident = findIdentity(kLabel, 60*60*24);
    Assert(ident, @"Couldn't find identity");
#endif

    NSData* digest = MYGetCertificateDigest(certRef);
    Log(@"Cert digest = %@", digest);
    Assert(digest);
}


#if 0
#import "MYCertificateRequest.h"
// This function was used to generate the "generic.cer" resource file
TestCase(CreateCertTemplate) {
    MYPrivateKey *privateKey = [MYPrivateKey generateRSAKeyPairOfSize: 2048
                                                                label: nil
                                                       applicationTag: nil
                                                                error: NULL];
    MYCertificateRequest *pcert = [[MYCertificateRequest alloc] initWithPublicKey: privateKey.publicKey];
    MYCertificateName *subject = pcert.subject;
    subject.commonName = @"anon";
    subject.nameDescription = @"An anonymous self-signed certificate";
    subject.emailAddress = @"anon@example.com";
    pcert.keyUsage = kKeyUsageDigitalSignature | kKeyUsageDataEncipherment | kKeyUsageKeyCertSign;
    pcert.extendedKeyUsage = [NSSet setWithObjects: kExtendedKeyUsageServerAuthOID,kExtendedKeyUsageEmailProtectionOID, nil];
    NSError *error;
    NSData *certData = [pcert selfSignWithPrivateKey: privateKey error: &error];
    [certData writeToFile: @"/tmp/generic.cer" atomically: NO];
}
#endif

#endif //DEBUG


// Original self-signed certificate created by Apple's Certificate Assistant app, saved as DER.
// Hex dump created by:  hexdump -e '"\t" 16/1 "0x%02x, " "\n"' generic.cer
// Also, data was truncated to remove the trailing 256 bytes of signature data,
// which gets replaced anyway.
static uint8_t const kCertTemplate[499] = {
	0x30, 0x82, 0x02, 0xef, 0x30, 0x82, 0x01, 0xd7, 0xa0, 0x03, 0x02, 0x01, 0x02, 0x02, 0x01, 0x01,
	0x30, 0x0b, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x30, 0x21, 0x31,
	0x12, 0x30, 0x10, 0x06, 0x03, 0x55, 0x04, 0x03, 0x0c, 0x09, 0x41, 0x6e, 0x6f, 0x6e, 0x79, 0x6d,
	0x6f, 0x75, 0x73, 0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55, 0x53,
	0x30, 0x1e, 0x17, 0x0d, 0x31, 0x35, 0x30, 0x37, 0x31, 0x36, 0x31, 0x38, 0x33, 0x31, 0x33, 0x36,
	0x5a, 0x17, 0x0d, 0x33, 0x35, 0x30, 0x37, 0x31, 0x31, 0x31, 0x38, 0x33, 0x31, 0x33, 0x36, 0x5a,
	0x30, 0x21, 0x31, 0x12, 0x30, 0x10, 0x06, 0x03, 0x55, 0x04, 0x03, 0x0c, 0x09, 0x41, 0x6e, 0x6f,
	0x6e, 0x79, 0x6d, 0x6f, 0x75, 0x73, 0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13,
	0x02, 0x55, 0x53, 0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7,
	0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00, 0x30, 0x82, 0x01, 0x0a, 0x02,
	0x82, 0x01, 0x01, 0x00, 0xb7, 0xe5, 0x5d, 0x6b, 0x7b, 0xc8, 0x40, 0xd3, 0xd1, 0x42, 0x48, 0x3a,
	0xcf, 0x25, 0x1e, 0xca, 0xe6, 0xc9, 0x06, 0x63, 0x78, 0x7d, 0x07, 0xf8, 0xc5, 0xb8, 0x24, 0x0f,
	0x15, 0x97, 0xf6, 0xc5, 0xcc, 0xea, 0x07, 0xd0, 0x7d, 0xcc, 0x01, 0xc5, 0x2f, 0xb8, 0x53, 0xf9,
	0x77, 0xec, 0xfa, 0x49, 0xf9, 0x0d, 0x50, 0xa9, 0xff, 0x8a, 0x28, 0x10, 0xea, 0x41, 0x52, 0x08,
	0x84, 0x25, 0x12, 0xb5, 0x5f, 0x65, 0x18, 0x24, 0x2d, 0x3c, 0xb1, 0x3a, 0x27, 0xbe, 0xda, 0xaf,
	0x7a, 0x2f, 0xd3, 0x97, 0xbd, 0xd3, 0x0e, 0xc4, 0x5a, 0xea, 0xe4, 0xc9, 0x46, 0xe9, 0x4e, 0x44,
	0xbe, 0xb8, 0x27, 0x23, 0xe6, 0xb1, 0xca, 0xf9, 0x53, 0x2f, 0x17, 0x41, 0xd3, 0x33, 0x0e, 0xdd,
	0xea, 0x54, 0x18, 0xe3, 0x5e, 0x7f, 0x1d, 0xba, 0xa6, 0xfb, 0x2e, 0xbc, 0x47, 0x78, 0x9d, 0xc0,
	0x8f, 0xac, 0xe8, 0xfd, 0x10, 0xf5, 0x3f, 0x60, 0x93, 0x17, 0xe3, 0x99, 0xd3, 0x01, 0xf5, 0x95,
	0x80, 0x79, 0xb6, 0xa0, 0xb4, 0x1d, 0x54, 0x70, 0x91, 0xeb, 0xd9, 0x84, 0x9b, 0x9c, 0x29, 0xc5,
	0xfe, 0x83, 0xbf, 0xac, 0x55, 0xcd, 0xd0, 0xe3, 0x06, 0x6b, 0x14, 0x75, 0xc9, 0x8e, 0xa0, 0xc8,
	0x60, 0x01, 0xf1, 0xb1, 0x0f, 0xd6, 0x68, 0xc2, 0x79, 0xe2, 0x1a, 0x33, 0x77, 0x18, 0x04, 0x33,
	0x70, 0x45, 0x50, 0x79, 0x8d, 0x5b, 0xe8, 0x74, 0xf1, 0x22, 0xbd, 0xfc, 0xcd, 0x3f, 0xd4, 0xdc,
	0x9b, 0xad, 0xfb, 0x12, 0x4b, 0x27, 0xe6, 0xa3, 0xff, 0x14, 0xa6, 0x90, 0x6d, 0x59, 0x72, 0xe5,
	0xae, 0x95, 0x73, 0x32, 0x32, 0xdc, 0x8f, 0xc9, 0x45, 0x25, 0x8e, 0x4b, 0xe0, 0xaf, 0x3f, 0xb7,
	0x10, 0xf4, 0x26, 0x98, 0xdb, 0xaf, 0x4a, 0xef, 0xc4, 0x6a, 0x3d, 0x9c, 0xbf, 0xe9, 0xe5, 0xb3,
	0x06, 0xde, 0xad, 0x81, 0x02, 0x03, 0x01, 0x00, 0x01, 0xa3, 0x34, 0x30, 0x32, 0x30, 0x0e, 0x06,
	0x03, 0x55, 0x1d, 0x0f, 0x01, 0x01, 0xff, 0x04, 0x04, 0x03, 0x02, 0x07, 0x80, 0x30, 0x20, 0x06,
	0x03, 0x55, 0x1d, 0x25, 0x01, 0x01, 0xff, 0x04, 0x16, 0x30, 0x14, 0x06, 0x08, 0x2b, 0x06, 0x01,
	0x05, 0x05, 0x07, 0x03, 0x02, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01, 0x30,
	0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00, 0x03, 0x82,
	0x01, 0x01, 0x00
};


/*
 Copyright (c) 2014-15, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions
 and the following disclaimer in the documentation and/or other materials provided with the
 distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRI-
 BUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
 THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
