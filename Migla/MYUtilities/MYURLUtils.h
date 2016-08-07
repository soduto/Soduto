//
//  MYURLUtils.h
//  MYUtilities
//
//  Created by Jens Alfke on 5/15/12.
//  Copyright (c) 2012 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>


/** Shorthand for creating an NSURL. */
static inline NSURL* $url(NSString* str) {
    return [NSURL URLWithString: str];
}


@interface NSURL (MYUtilities)

/** The port number explicitly or implicitly specified by this URL. */
@property (readonly) UInt16 my_effectivePort;

/** YES if the scheme is 'https:'. */
@property (readonly) BOOL my_isHTTPS;

/** Returns a URL with just the scheme, host and port (if the port is nonstandard). */
- (NSURL*) my_baseURL;

/** The path and everything after it. This is what appears on the first line of an HTTP request. */
@property (readonly) NSString* my_pathAndQuery;

/** Removes the username and password components, if any, from a URL. */
@property (readonly) NSURL* my_URLByRemovingUser;

/** Returns the URL's absoluteString with the password, if any, replaced with "*****".
    Also, any query parameter whose name contains "token" will have its value changed to "*****". */
@property (readonly) NSString* my_sanitizedString;

/** Similar to my_sanitizedString, but returns only the URL's path (including query and fragment). */
@property (readonly) NSString* my_sanitizedPath;

/** Returns an NSURLProtectionSpace initialized based on the attributes of this URL
    (host, effective port, scheme) and the given realm and authentication method. */
- (NSURLProtectionSpace*) my_protectionSpaceWithRealm: (NSString*)realm
                                 authenticationMethod: (NSString*)authenticationMethod;

/** Looks up a credential for this URL.
    It will be looked up from the shared NSURLCredentialStorage (ie. the Keychain),
    unless using a username and password hardcoded in the URL itself. */
- (NSURLCredential*) my_credentialForRealm: (NSString*)realm
                      authenticationMethod: (NSString*)authenticationMethod;

/** Proxy configuration settings for this URL, or nil if none are in effect.
    Keys in this dictionary are defined in CFProxySupport.h. */
@property (readonly) NSDictionary* my_proxySettings;

@end
