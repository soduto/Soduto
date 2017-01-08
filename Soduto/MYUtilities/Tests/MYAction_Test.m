//
//  MYAction_Test.m
//  MYUtilities
//
//  Created by Jens Alfke on 8/28/15.
//  Copyright © 2015 Jens Alfke. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MYAction.h"
#import "MYErrorUtils.h"


@interface MYAction_Test : XCTestCase
@end


@implementation MYAction_Test


- (void) testSuccess {
    __block NSMutableString* str = [@"Test" mutableCopy];

    MYAction* seq = [MYAction new];
    [seq addPerform: ^BOOL(NSError** outError) {
        [str insertString: @"his is a t" atIndex:1];
        return YES;
    } backOut: ^BOOL(NSError** outError) {
        [str deleteCharactersInRange: NSMakeRange(1, 10)];
        return YES;
    } cleanUp: ^BOOL(NSError** outError) {
        return YES;
    }];

    NSError* error;
    XCTAssert([seq run: &error]);
    XCTAssertEqualObjects(str, @"This is a test");
}

- (void) testFailure {
    __block NSMutableString* str = [@"Test" mutableCopy];
    NSError* theError = MYError(1, @"test", @"yikes");

    MYAction* seq = [MYAction new];
    [seq addPerform: ^BOOL(NSError** outError) {
        [str insertString: @"his is a t" atIndex:1];
        return YES;
    } backOut: ^BOOL(NSError** outError) {
        [str deleteCharactersInRange: NSMakeRange(1, 10)];
        return YES;
    } cleanUp: ^BOOL(NSError** outError) {
        return YES;
    }];

    [seq addPerform: ^BOOL(NSError** outError) {
        *outError = theError;
        return NO;
    } backOut: ^BOOL(NSError** outError) {
        XCTFail(@"Shouldn't back out this step");
        return NO;
    } cleanUp: ^BOOL(NSError** outError) {
        XCTFail(@"Shouldn't clean up this step");
        return NO;
    }];

    NSError* error;
    XCTAssert(![seq run: &error]);
    XCTAssertEqualObjects(error, theError);
    XCTAssertEqualObjects(seq.error, theError);
    XCTAssertEqual(seq.failedStep, 1u);
    XCTAssertEqualObjects(str, @"Test");
}

@end
