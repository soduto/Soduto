//
//  MYErrorUtils.m
//  MYUtilities
//
//  Created by Jens Alfke on 2/25/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "MYErrorUtils.h"
#import "Test.h"
#import "MYLogging.h"
#import "MYURLUtils.h"
#import "CollectionUtils.h"
#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#undef MYERRORUTILS_USE_SECURITY_API
#endif

#if MYERRORUTILS_USE_SECURITY_API
#import <Security/SecBase.h>
#endif


NSString* const MYErrorDomain = @"MYErrorDomain";


static NSError *MYMakeErrorV( int errorCode, NSString *domain, NSString *message, va_list args )
{
    message = [[NSString alloc] initWithFormat: message arguments: args];
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                                      message, NSLocalizedDescriptionKey,
                                                      nil];
    MYRelease(message);
    return [NSError errorWithDomain: domain
                               code: errorCode
                           userInfo: userInfo];
}


NSError *MYError( int errorCode, NSString *domain, NSString *message, ... )
{
    va_list args;
    va_start(args,message);
    NSError *error = MYMakeErrorV(errorCode,domain,message,args);
    va_end(args);
    return error;
}


BOOL MYReturnError( NSError **outError,
                    int errorCode, NSString *domain, NSString *messageFormat, ... ) 
{
    if (errorCode) {
        if (outError) {
            va_list args;
            va_start(args,messageFormat);
            *outError = MYMakeErrorV(errorCode, domain, messageFormat, args);
            va_end(args);
            Log(@"MYReturnError: %@",*outError);
        } else {
            Log(@"MYReturnError: %@/%i",domain,errorCode);
        }
        return NO;
    } else
        return YES;
}


BOOL MYMiscError( NSError **error, NSString *message, ... )
{
    if (error) {
        va_list args;
        va_start(args,message);
        *error = MYMakeErrorV(kMYErrorMisc,MYErrorDomain, message,args);
        va_end(args);
    }
    return NO;
}


NSError *MYErrorFromErrno(void)
{
    int err = errno;
    if (!err)
        return nil;
    return MYError(err, NSPOSIXErrorDomain, @"%s", strerror(err));
}


static NSString* printableOSType( OSType t ) {
    if (t < 0x20202020 || t > 0x7e7e7e7e)
        return nil;
    union {
        OSType ostype;
        unsigned char ch[4];
    } buf;
    buf.ostype = CFSwapInt32HostToBig(t);
    for (int i=0; i<4; i++)
        if (buf.ch[i] < 0x20 || buf.ch[i] > 0x7E)
            return nil;
    return MYAutorelease([[NSString alloc] initWithBytes: &buf.ch length: 4 encoding: NSMacOSRomanStringEncoding]);
}


static NSString* printableErrorCode( NSInteger code ) {
    if ((OSStatus)code < -99999)
        return $sprintf(@"%u", (unsigned)code);       // CSSM errors are huge unsigned values > 0x80000000
    NSString *result = printableOSType((OSType)code);
    if (result)
        return result;                      // CoreAudio errors are OSTypes (4-char strings)
    return $sprintf(@"%ld", (long)code);    // Default: OSStatus and errno values are signed
}

static NSString* MYShortErrorDomainName( NSString *domain ) {
    if ([domain hasPrefix: @"kCFErrorDomain"])
        domain = $sprintf(@"CF%@Error", [domain substringFromIndex: 14]);
    else {
        if ([domain hasSuffix: @"Domain"])
            domain = [domain substringToIndex: domain.length - 6];
    }
    return domain;
}

static NSString* MYErrorDesc( NSString *domain, NSInteger code ) {
    if (code == 0)
        return nil;
    if (!domain)
        return printableErrorCode(code);
    NSString *result = nil;
    
    if ($equal(domain,NSPOSIXErrorDomain)) {
        // Interpret POSIX errors via strerror
        // (which unfortunately returns a description, not the name of the constant)
        const char *name = strerror((int)code);
        if (name) {
            result = [NSString stringWithCString: name encoding: NSASCIIStringEncoding];
            if ([result hasPrefix: @"Unknown error"])
                result = nil;
        }
    } 
#if !TARGET_OS_IPHONE || defined(__SEC_TYPES__)
    else if ($equal(domain,NSOSStatusErrorDomain)) {
        // If it's an OSStatus, check whether CarbonCore knows its name:
        const char *name = NULL;
#if !TARGET_OS_IPHONE
#if (__MAC_OS_X_VERSION_MIN_REQUIRED < 1080)
        name = GetMacOSStatusErrorString((int)code);
#endif
#endif
        if (name && *name)
            result = [NSString stringWithCString: name encoding: NSMacOSRomanStringEncoding];
        else {
#if MYERRORUTILS_USE_SECURITY_API
            NSString* msg = CFBridgingRelease(SecCopyErrorMessageString((OSStatus)code,NULL));
            if (![msg hasPrefix: @"OSStatus "])
                result = $sprintf(@"SecError: %@", msg);
#endif
        }
    }
#endif

#if MYERRORUTILS_USE_STRINGS_FILE
    if (!result) {
        // Look up errors in string files keyed by the domain name:
        NSString *codeStr = printableErrorCode(code);
        NSString *table = [@"MYError_" stringByAppendingString: domain];
        result = [[NSBundle mainBundle] localizedStringForKey: codeStr value: @"?" table: table];
        if ([result isEqualToString: @"?"])
            result = nil;
    }
#endif
    return result;
}

NSString* MYErrorName( NSString *domain, NSInteger code ) {
    NSString* result = MYErrorDesc(domain, code);
    NSString* codeStr = $sprintf(@"%@ %@", MYShortErrorDomainName(domain), printableErrorCode(code));
    return result ? $sprintf(@"%@ (%@)", result, codeStr) : codeStr;
}


NSError* MYWrapError(NSError* error, NSString* domain, NSInteger code, NSDictionary* userInfo) {
    NSMutableDictionary* info = userInfo ? userInfo.mutableCopy : $mdict();
    info[NSUnderlyingErrorKey] = error;
    if (!info[NSLocalizedDescriptionKey]) {
        NSString* desc = error.my_nonDefaultLocalizedDescription;
        if (desc)
            info[NSLocalizedDescriptionKey] = desc;
    }
    return [NSError errorWithDomain: domain code: code userInfo: info];
}


// map is [domain -> [code -> (domain, code)]
NSError* MYMapError(NSError* error, NSDictionary* map) {
    if (!error) return nil;
    NSDictionary* codeMap = map[error.domain];
    NSArray* nu = codeMap[@(error.code)];
    if (nu)
        return MYWrapError(error, nu[0], [nu[1] integerValue], nil);
    return error;
}




@implementation NSError (MYUtils)

- (NSError*) my_errorByPrependingMessage: (NSString*)message
{
    if( message.length ) {
        NSDictionary *oldUserInfo = self.userInfo;
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        if( oldUserInfo )
            [userInfo addEntriesFromDictionary: oldUserInfo];
        NSString *desc = [oldUserInfo objectForKey: NSLocalizedDescriptionKey];
        if( desc )
            message = $sprintf(@"%@: %@", message, desc);
        [userInfo setObject: message forKey: NSLocalizedDescriptionKey];
        return [NSError errorWithDomain: self.domain
                                   code: self.code
                               userInfo: userInfo];
    } else
        return self;
}

- (NSString*) my_nameOfCode {
    return MYErrorName(self.domain, self.code);
}

- (BOOL) my_hasDomain: (NSString*)domain code: (NSInteger)code {
    return self.code == code && [self.domain isEqualToString: domain];
}

- (BOOL) my_isFileExistsError {
    NSString* domain = self.domain;
    NSInteger code = self.code;
    return ($equal(domain, NSPOSIXErrorDomain) && code == EEXIST)
        || ($equal(domain, NSCocoaErrorDomain) && code == NSFileWriteFileExistsError);
}

- (BOOL) my_isFileNotFoundError {
    NSString* domain = self.domain;
    NSInteger code = self.code;
    return ($equal(domain, NSPOSIXErrorDomain) && code == ENOENT)
        || ($equal(domain, NSCocoaErrorDomain) && (code == NSFileNoSuchFileError
                                                   || code == NSFileReadNoSuchFileError));
}

- (NSURL*) my_failingURL {
    NSDictionary* userInfo = self.userInfo;
    NSURL *url = userInfo[NSURLErrorFailingURLErrorKey] ?: userInfo[NSURLErrorKey];
    if (!url) {
        NSString* urlStr = userInfo[NSURLErrorFailingURLStringErrorKey];
        if (urlStr)
            url = [NSURL URLWithString: urlStr];
    }
    return url;
}

- (NSString*) my_compactDescription {
    NSDictionary* userInfo = self.userInfo;
    NSMutableString* s = [NSMutableString stringWithFormat: @"%@[%zd",
                          MYShortErrorDomainName(self.domain), self.code];
    NSString* desc = self.my_nonDefaultLocalizedDescription;
    if (desc)
        [s appendFormat: @", \"%@\"", desc];
    NSURL *url = self.my_failingURL;
    if (url)
        [s appendFormat: @", <%@>", url.my_sanitizedString];
    NSString* filePath = userInfo[NSFilePathErrorKey];
    if (filePath)
        [s appendFormat: @", '%@'", filePath];
    [s appendString: @"]"];
    NSError* underlying = userInfo[NSUnderlyingErrorKey];
    if (underlying) {
        [s appendString: @"<--"];
        [s appendString: underlying.my_compactDescription];
    }
    return s;
}

- (NSString*) my_nonDefaultLocalizedDescription {
    NSString* desc = self.userInfo[NSLocalizedDescriptionKey];
    if (desc)
        return desc;
    if ([[NSError class] respondsToSelector: @selector(userInfoValueProviderForDomain:)]) {
        id (^provider)(NSError *err, NSString *userInfoKey) =
                                                [NSError userInfoValueProviderForDomain: self.domain];
        if (provider) {
            desc = provider(self, NSLocalizedDescriptionKey)
                    ?: provider(self, NSLocalizedFailureReasonErrorKey);
        }
    }
    if (!desc)
        desc = MYErrorDesc(self.domain, self.code);
    return desc;
}

@end


TestCase(MYErrorUtils) {
    CAssertEqual(printableOSType('abcd'), @"abcd");
    CAssertEqual(printableOSType('    '), @"    ");
    CAssertEqual(printableOSType(0x7e7e7e7e), @"~~~~");
    CAssertEqual(printableOSType(0x7e7F7e7e), nil);
    CAssertEqual(printableOSType(0x7e0D7e7e), nil);
    CAssertEqual(printableOSType(0), nil);
    CAssertEqual(printableOSType((OSType)-123456), nil);

    CAssertEqual(MYErrorName(nil,0),      nil);
    CAssertEqual(MYErrorName(nil,12345),  @"12345");
    CAssertEqual(MYErrorName(nil,1),      @"1");
    CAssertEqual(MYErrorName(nil,-1),     @"-1");
    CAssertEqual(MYErrorName(nil,12345),  @"12345");
    CAssertEqual(MYErrorName(nil,-12345), @"-12345");
    CAssertEqual(MYErrorName(nil,2147549184u), @"2147549184");  // that's 0x80010000
    
    CAssertEqual(MYErrorName(@"foobar",0), nil);
    CAssertEqual(MYErrorName(@"foobar",'fmt?'), @"foobar fmt?");
    CAssertEqual(MYErrorName(@"foobar",1), @"foobar 1");
    CAssertEqual(MYErrorName(@"FoobarErrorDomain",-1), @"Foobar -1");
    CAssertEqual(MYErrorName(@"NSFoobarErrorDomain",12345), @"Foobar 12345");

    NSError *err;
    err = [NSError errorWithDomain: NSPOSIXErrorDomain code: EPERM userInfo: nil];
    CAssertEqual(err.my_nameOfCode, @"Operation not permitted (POSIX 1)");
    err = [NSError errorWithDomain: NSPOSIXErrorDomain code: 12345 userInfo: nil];
    CAssertEqual(err.my_nameOfCode, @"POSIX 12345");
    
#if !TARGET_OS_IPHONE
#if (__MAC_OS_X_VERSION_MIN_REQUIRED < 1080)
    err = [NSError errorWithDomain: NSOSStatusErrorDomain code: paramErr userInfo: nil];
    CAssertEqual(err.my_nameOfCode, @"paramErr (OSStatus -50)");
    err = [NSError errorWithDomain: NSOSStatusErrorDomain code: fnfErr userInfo: nil];
    CAssertEqual(err.my_nameOfCode, @"fnfErr (OSStatus -43)");
    err = [NSError errorWithDomain: NSOSStatusErrorDomain code: -25291 userInfo: nil];
    CAssertEqual(err.my_nameOfCode, @"errKCNotAvailable / errSecNotAvailable (OSStatus -25291)");
#endif
#if MYERRORUTILS_USE_SECURITY_API
    err = [NSError errorWithDomain: NSOSStatusErrorDomain code: -25260 userInfo: nil];
    CAssertEqual(err.my_nameOfCode, @"Passphrase is required for import/export. (OSStatus -25260)");
#endif
#endif
    err = [NSError errorWithDomain: NSOSStatusErrorDomain code: 12345 userInfo: nil];
    CAssertEqual(err.my_nameOfCode, @"OSStatus 12345");

    err = [NSError errorWithDomain: @"CSSMErrorDomain" code: 2147549184u userInfo: nil];
#if MYERRORUTILS_USE_SECURITY_API
    CAssertEqual(err.my_nameOfCode, @"CSSM_CSSM_BASE_ERROR (CSSM 2147549184)");
    // If that assertion fails, you probably need to add MYError_CSSMErrorDomain.strings to your target.
#else
    CAssertEqual(err.my_nameOfCode, @"CSSM 2147549184");
#endif
    err = [NSError errorWithDomain: (id)kCFErrorDomainCocoa code: 100 userInfo: nil];
    CAssertEqual(err.my_nameOfCode, @"Cocoa 100");
}



/*
 Copyright (c) 2008-2013, Jens Alfke <jens@mooseyard.com>. All rights reserved.

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
