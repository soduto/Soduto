//
//  Test_Assertions.m
//  MYUtilities
//
//  Created by Jens Alfke on 8/11/14.
//
//

#import "Test.h"


#if !__has_feature(objc_arc)
#error This source file must be compiled with ARC
#endif


void _AssertFailed(const void *selOrFn, const char *sourceFile, int sourceLine,
                    const char *condString, NSString *message, ... )
{
    if( message ) {
        va_list args;
        va_start(args,message);
        message = [[NSString alloc] initWithFormat: message arguments: args];
        NSLog(@"*** ASSERTION FAILED: %@", message);
        message = [@"Assertion failed: " stringByAppendingString: message];
        va_end(args);
    } else {
        message = [NSString stringWithUTF8String: condString];
        NSLog(@"*** ASSERTION FAILED: %@", message);
    }
    [[NSAssertionHandler currentHandler] handleFailureInFunction: [NSString stringWithUTF8String:selOrFn]
                                                            file: [NSString stringWithUTF8String: sourceFile]
                                                      lineNumber: sourceLine
                                                     description: @"%@", message];
    abort(); // unreachable, but appeases compiler
}


void _AssertAbstractMethodFailed( id rcvr, SEL cmd)
{
    [NSException raise: NSInternalInconsistencyException 
                format: @"Class %@ forgot to implement abstract method %@",
                         [rcvr class], NSStringFromSelector(cmd)];
    abort(); // unreachable, but appeases compiler
}


static NSString* _WhyUnequalObjects(id a, id b, NSString* indent, BOOL *inequal);

static NSString* WhyUnequalArrays(NSArray* a, NSArray* b, NSString* indent, BOOL *inequal) {
    indent = [indent stringByAppendingString: @"\t"];
    NSMutableString* out = [NSMutableString stringWithString: @"Unequal NSArrays:"];
    NSUInteger na = a.count, nb = b.count, n = MAX(na, nb);
    for (NSUInteger i = 0; i < n; i++) {
        id aa = (i < na) ? a[i] : nil;
        id bb = (i < nb) ? b[i] : nil;
        NSString* diff = _WhyUnequalObjects(aa, bb, indent, inequal);
        if (diff)
            [out appendFormat: @"\n%@%u: %@", indent, (unsigned)i, diff];
    }
    return out;
}


static NSString* WhyUnequalDictionaries(NSDictionary* a, NSDictionary* b, NSString* indent, BOOL *inequal) {
    indent = [indent stringByAppendingString: @"\t"];
    NSMutableString* out = [NSMutableString stringWithString: @"Unequal NSDictionaries:"];
    for (id key in a) {
        NSString* diff = _WhyUnequalObjects(a[key], b[key], indent, inequal);
        if (diff)
            [out appendFormat: @"\n%@%@: %@", indent, [key my_compactDescription], diff];
    }
    for (id key in b) {
        if (!a[key]) {
            NSString* diff = _WhyUnequalObjects(a[key], b[key], indent, inequal);
            [out appendFormat: @"\n%@%@: %@", indent, [key my_compactDescription], diff];
        }
    }
    return out;
}


static NSString* _WhyUnequalObjects(id a, id b, NSString* indent, BOOL *inequal) {
    if ($equal(a, b))
        return nil;
    if (indent == nil)
        indent = @"";
    if ([a isKindOfClass: [NSDictionary class]]) {
        if ([b isKindOfClass: [NSDictionary class]]) {
            return WhyUnequalDictionaries(a, b, indent, inequal);
        }
    } else if ([a isKindOfClass: [NSArray class]]) {
        if ([b isKindOfClass: [NSArray class]]) {
            return WhyUnequalArrays(a, b, indent, inequal);
        }
    } else if ([a isKindOfClass: [NSNumber class]]) {
        if ([b isKindOfClass: [NSNumber class]]) {
            double na = [a doubleValue], nb = [b doubleValue];
            if (fabs(na-nb)/fmax(fabs(na),fabs(nb)) < 1.0e-6)
                return nil; // numbers are equal within rounding error
        }
    }

    *inequal = YES;
    return $sprintf(@"%@  ≠  %@", [a my_compactDescription], [b my_compactDescription]);
}


NSString* WhyUnequalObjects(id a, id b) {
    BOOL inequal = NO;
    NSString* why = _WhyUnequalObjects(a, b, nil, &inequal);
    if (!inequal)
        why = nil;
    return why;
}


void _AssertEqual(id val, id expected, const char* valExpr,
                  const char* selOrFn, const char* sourceFile, int sourceLine) {
    if ($equal(val, expected))
        return;
    NSString* diff = WhyUnequalObjects(val, expected);
    if (!diff)
        return; // they're "equal-ish"
    if ([diff rangeOfString: @"\n"].length > 0) {
        // If diff is multi-line, log it but don't put it in the assertion message
        NSLog(@"\n*** Actual vs. expected value of %s :%@\n", valExpr, diff);
        diff = @"(see above)";
    }
    _AssertFailed(selOrFn, sourceFile, sourceLine, valExpr, @"Unexpected value of %s: %@",
                  valExpr, diff);
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
