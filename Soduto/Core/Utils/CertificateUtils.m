//
//  CertificateUtils.m
//  Soduto
//
//  Created by Giedrius Stanevičius on 2017-01-12.
//  Copyright © 2017 Soduto. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <openssl/pem.h>
#import <openssl/x509.h>
#import <openssl/x509v3.h>
#import "CertificateUtils.h"

/* Generates a 2048-bit RSA key. */
EVP_PKEY * generate_key() {
    /* Allocate memory for the EVP_PKEY structure. */
    EVP_PKEY * pkey = EVP_PKEY_new();
    if (!pkey) {
        NSLog(@"Unable to create EVP_PKEY structure.");
        return NULL;
    }
    
    /* Allocate BIGNUM structure for exponent */
    BIGNUM *bne = BN_new();
    if (!bne) {
        NSLog(@"Unable to create BIGNUM structure.");
        EVP_PKEY_free(pkey);
        return NULL;
    }
    
    /* Assign exponent value */
    if (BN_set_word(bne, RSA_F4) != 1) {
        NSLog(@"Unable to assign exponent value to BIGNUM.");
        BN_free(bne);
        EVP_PKEY_free(pkey);
        return NULL;
    }
    
    /* Allocate RSA structure */
    RSA *rsa = RSA_new();
    if (!rsa) {
        NSLog(@"Unable to create RSA structure.");
        BN_free(bne);
        EVP_PKEY_free(pkey);
        return NULL;
    }
    
    /* Generate the RSA key. */
    if (RSA_generate_key_ex(rsa, 2048, bne, NULL) != 1) {
        NSLog(@"Failed to generate 2048-bit RSA key.");
        RSA_free(rsa);
        BN_free(bne);
        EVP_PKEY_free(pkey);
        return NULL;
    }
    
    /* Assign RSA key to pkey */
    if (EVP_PKEY_assign_RSA(pkey, rsa) != 1) {
        NSLog(@"Unable to assign RSA key to pkey.");
        RSA_free(rsa);
        BN_free(bne);
        EVP_PKEY_free(pkey);
        return NULL;
    }
    
    /* The key has been generated, return it. */
    return pkey;
}

/* Add an extension to a certificate */
BOOL add_extension(X509 *cert, int nid, char *value) {
    X509_EXTENSION *ex = NULL;
    X509V3_CTX ctx;
    
    // This sets the 'context' of the extensions. No configuration database
    X509V3_set_ctx_nodb(&ctx);
    
    // Issuer and subject certs: both the target since it is self signed, no request and no CRL
    X509V3_set_ctx(&ctx, cert, cert, NULL, NULL, 0);
    ex = X509V3_EXT_conf_nid(NULL, &ctx, nid, value);
    if (!ex) {
        return NO;
    }
    
    int result = X509_add_ext(cert, ex, -1);
    
    X509_EXTENSION_free(ex);
    
    return (result == 0) ? YES : NO;
}

/* Generates a self-signed x509 certificate. */
X509 * generate_x509(EVP_PKEY * pkey, const char *commonName) {
    /* Allocate memory for the X509 structure. */
    X509 * x509 = X509_new();
    if (!x509) {
        NSLog(@"Unable to create X509 structure.");
        return NULL;
    }
    
    X509_set_version(x509, 2);
    
    /* Set the serial number. */
    ASN1_INTEGER_set(X509_get_serialNumber(x509), 1);
    
    /* Set certificate valid time interval */
    X509_gmtime_adj(X509_get_notBefore(x509), -365 * 24 * 60 * 60);
    X509_gmtime_adj(X509_get_notAfter(x509), 10 * 365 * 24 * 60 * 60);
    
    /* Set the public key for our certificate. */
    X509_set_pubkey(x509, pkey);
    
    /* We want to copy the subject name to the issuer name. */
    X509_NAME * name = X509_get_subject_name(x509);
    
    /* Set the country code and common name. */
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, (unsigned char *)commonName,       -1, -1, 0);
    X509_NAME_add_entry_by_txt(name, "O",  MBSTRING_ASC, (unsigned char *)"Soduto",            -1, -1, 0);
    
    /* Now set the issuer name. */
    X509_set_issuer_name(x509, name);
    
    /* Add usage extensions */
//    add_extension(x509, NID_key_usage, "critical,digitalSignature");
//    add_extension(x509, NID_ext_key_usage, "critical,serverAuth,clientAuth");
    
    /* Actually sign the certificate with our key. */
    if (!X509_sign(x509, pkey, EVP_sha256())) {
        NSLog(@"Error signing certificate.");
        X509_free(x509);
        return NULL;
    }
    
    return x509;
}

EVP_PKEY * unserialize_key(NSData *keyData) {
    BIO* bio = BIO_new_mem_buf(keyData.bytes, (int)keyData.length);
    if (!bio) {
        NSLog(@"Unable to create BIO structure.");
        return NULL;
    }
    
    EVP_PKEY * pkey = PEM_read_bio_PrivateKey(bio, NULL , NULL, NULL);
    if (!pkey) {
        NSLog(@"Unable to read private key from given data.");
    }
    
    BIO_free(bio);
    
    return pkey;
}


NSData *serialize_identity(EVP_PKEY * pkey, X509 * x509) {
    NSData *data = NULL;
    
    BIO* bio = BIO_new(BIO_s_mem());
    if (!bio) {
        NSLog(@"Unable to create BIO structure.");
        return data;
    }
    
    PEM_write_bio_PrivateKey(bio, pkey, NULL, NULL, 0, NULL, NULL);
    PEM_write_bio_X509(bio, x509);
    
    BUF_MEM *bptr;
    BIO_get_mem_ptr(bio, &bptr);
    if (bptr) {
        data = [NSData dataWithBytes:bptr->data length:bptr->length];
    }
    BIO_set_close(bio, BIO_CLOSE);
    BIO_free(bio);
    
    return data;
}

/* Generate identity data: a private key and corresponding self-signed x509 certificate */
NSData *generateIdentity(NSString *commonName) {
    /* Generate the key. */
    EVP_PKEY * pkey = generate_key();
    if (!pkey) {
        return NULL;
    }
    
    /* Generate the certificate. */
    X509 * x509 = generate_x509(pkey, commonName.UTF8String);
    if (!x509) {
        EVP_PKEY_free(pkey);
        return NULL;
    }
    
    /* Write the private key and certificate out to a buffer. */
    NSData *data = serialize_identity(pkey, x509);
    
    EVP_PKEY_free(pkey);
    X509_free(x509);
    
    return data;
}

/* Generate identity data: a private key and corresponding self-signed x509 certificate */
NSData *generateIdentityWithPrivateKey(NSString *commonName, NSData *privateKeyData) {
    /* Unserialize the key. */
    EVP_PKEY * pkey = unserialize_key(privateKeyData);
    if (!pkey) {
        return NULL;
    }
    
    /* Generate the certificate. */
    X509 * x509 = generate_x509(pkey, commonName.UTF8String);
    if (!x509) {
        EVP_PKEY_free(pkey);
        return NULL;
    }
    
    /* Write the private key and certificate out to a buffer. */
    NSData *data = serialize_identity(pkey, x509);
    
    EVP_PKEY_free(pkey);
    X509_free(x509);
    
    return data;
}
