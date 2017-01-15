//
//  CertificateUtils.h
//  Soduto
//
//  Created by Giedrius Stanevičius on 2017-01-14.
//  Copyright © 2017 Soduto. All rights reserved.
//

#import <Foundation/Foundation.h>

NSData *generateIdentity(NSString *commonName);
NSData *generateIdentityWithPrivateKey(NSString *commonName, NSData *privateKeyData);
