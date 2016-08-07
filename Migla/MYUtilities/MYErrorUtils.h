//
//  MYErrorUtils.h
//  MYUtilities
//
//  Created by Jens Alfke on 2/25/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import <Foundation/NSError.h>
@class NSError, NSString;


extern NSString* const MYErrorDomain;

enum {
    /** "Miscellaneous" error code, set by MYMiscError.
        Handy during development, but before shipping you really should define
        individual error codes for each error condition. */
    kMYErrorMisc = 999999,
};


/** Creates an NSError in MYErrorDomain. */
NSError *MYError( int errorCode, NSString *domain, NSString *messageFormat, ... ) 
                                __attribute__ ((format (__NSString__, 3, 4)));

/** A variant of MYError, useful for returning from a method.
    If errorCode is nonzero, constructs an NSError and stores it into *outError,
    then returns NO. Otherwise returns YES. */
BOOL MYReturnError( NSError **outError,
                    int errorCode, NSString *domain, NSString *messageFormat, ... ) 
                                __attribute__ ((format (__NSString__, 4, 5)));

/** Convenience function for creating NSErrors.
    Stores an NSError into *error, and returns NO.
    Domain will be MYErrorDomain, code will be kMYErrorMisc.
    Handy during development, but before shipping you really should define
    individual error codes for each error condition. */
BOOL MYMiscError( NSError **outError, NSString *messageFormat, ... )
                                __attribute__ ((format (__NSString__, 2, 3)));

/** Returns an NSError based on the global variable 'errno'. Useful with POSIX calls. */
NSError *MYErrorFromErrno(void);

/** Utilities for converting NSErrors to user-readable (but geeky) strings.
    If your code uses Security or SSL APIs, you will probably want to #define
    the symbol MYERRORUTILS_USE_SECURITY_API in your precompiled header, which
    will enable the implementations of these functions to call Security API to
    look up error messages. (This is turned off by default because it creates
    a dependency on linking against Security.framework.)
 */
NSString* MYErrorName( NSString *domain, NSInteger code );

/** Returns a new NSError that points to the original one as its underlying error. */
NSError* MYWrapError(NSError* error, NSString* domain, NSInteger code, NSDictionary* userInfo);

/** Maps an error to a different error.
    The keys of `map` are error domains, and the values are dictionaries.
    Each dictionary's keys are error codes, and the values are arrays [domain, code].
    If there's no match, the original error is returned. */
NSError* MYMapError(NSError* error, NSDictionary* map);

@interface NSError (MYUtilities)
/** Prepends a message to the beginning of the receiver's existing message,
    and returns the modified NSError. */
- (NSError*) my_errorByPrependingMessage: (NSString*)message;

- (NSString*) my_nameOfCode;

- (BOOL) my_hasDomain: (NSString*)domain code: (NSInteger)code;

@property (readonly) BOOL my_isFileExistsError;
@property (readonly) BOOL my_isFileNotFoundError;

@property (readonly) NSURL* my_failingURL;

/** A nice informative-but-compact description of an NSError, for logging. */
@property (readonly) NSString* my_compactDescription;

@property (readonly) NSString* my_nonDefaultLocalizedDescription;
@end
