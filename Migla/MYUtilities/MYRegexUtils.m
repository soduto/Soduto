//
//  MYRegexUtils.m
//  MYUtilities
//
//  Created by Jens Alfke on 6/28/12.
//  Copyright (c) 2012 Jens Alfke. All rights reserved.
//

#import "MYRegexUtils.h"
#import "Test.h"


NSRegularExpression* $regex( NSString* pattern ) {
    NSError* error;
    NSRegularExpression* r = [NSRegularExpression regularExpressionWithPattern: pattern
                                                                       options: 0
                                                                         error: &error];
    CAssert(r, @"Invalid regex '%@': %@", pattern, error.my_compactDescription);
    return r;
}
