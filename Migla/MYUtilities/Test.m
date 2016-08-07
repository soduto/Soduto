//
//  Test.m
//  MYUtilities
//
//  Created by Jens Alfke on 1/5/08.
//  Copyright 2008-2013 Jens Alfke. All rights reserved.
//

#import "Test.h"


#if !__has_feature(objc_arc)
#error This source file must be compiled with ARC
#endif


#if MY_ENABLE_TESTS

#import "ExceptionUtils.h"

BOOL gRunningTestCase;

struct TestCaseLink *gAllTestCases;
static int sPassed, sFailed;
static NSMutableArray* sFailedTestNames;
static struct TestCaseLink *sCurrentTest;
static int sCurTestCaseExceptions;
static NSMutableArray* sAfterTestBlocks;

#if TARGET_OS_IPHONE
#define XML_REPORT 0 // iOS doesn't have NSXML
#else
#define XML_REPORT 1
#endif

#if XML_REPORT
static NSXMLElement* sReportXML;
#endif

static BOOL CheckCoverage(const char* testName);
static BOOL CheckUncalledCoverage(void);


static void TestCaseExceptionReporter( NSException *x ) {
    sCurTestCaseExceptions++;
    fflush(stderr);
    Log(@"XXX FAILED test case -- backtrace:\n%@\n\n", x.my_callStack);
}

static void ReportTestCase(struct TestCaseLink *test, NSString* failureType, NSString* failureMessage) {
#if XML_REPORT
    if (!sReportXML)
        return;
    NSString* name = [NSString stringWithUTF8String: test->name];
    NSXMLElement* testcase = [NSXMLElement elementWithName: @"testcase"];
    [testcase setAttributesWithDictionary: @{@"name": name,
                                             @"classname": name}];
    if ($equal(failureType, @"skipped")) {
        NSXMLElement* skipped = [NSXMLElement elementWithName: @"skipped"];
        if (failureMessage)
            skipped.stringValue = failureMessage;
        [testcase addChild: skipped];
    } else if (failureType != nil) {
        NSXMLElement* failure = [NSXMLElement elementWithName: @"failure"];
        [failure setAttributesWithDictionary: @{@"type": failureType}];
        if (failureMessage)
            [failure setStringValue: failureMessage];
        [testcase addChild: failure];
    }
    [sReportXML addChild: testcase];
#endif
}

static void RecordFailedTest( struct TestCaseLink *test ) {
    if (!sFailedTestNames)
        sFailedTestNames = [[NSMutableArray alloc] init];
    [sFailedTestNames addObject: [NSString stringWithUTF8String: test->name]];
}

void AfterThisTest(void (^block)(void)) {
    if (sCurrentTest)
        [sAfterTestBlocks insertObject: [[block copy] autorelease] atIndex: 0];  // LIFO
}

static BOOL RunTestCase( struct TestCaseLink *test )
{
    if( !test->testptr )
        return YES;     // already ran this test

#ifndef MY_DISABLE_LOGGING
    BOOL oldLogging = EnableLog(YES);
#endif
    BOOL wasRunningTestCase = gRunningTestCase;
    gRunningTestCase = YES;
    struct TestCaseLink* prevTest = sCurrentTest;
    sCurrentTest = test;

    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSMutableArray* savedAfterTestBlocks = sAfterTestBlocks;
    sAfterTestBlocks = [NSMutableArray array];
    Log(@"=== Testing %s ...",test->name);
    @try{
        sCurTestCaseExceptions = 0;
        MYSetExceptionReporter(&TestCaseExceptionReporter);

        test->testptr();    //SHAZAM!

        // Run any after-test blocks that were registered:
        NSArray* blocks = sAfterTestBlocks;
        sAfterTestBlocks = nil;
        for (void (^block)() in blocks)
            block();

        if (!CheckCoverage(test->name)) {
            Log(@"XXX FAILED test case '%s' due to coverage failures", test->name);
            sFailed++;
            RecordFailedTest(test);
            ReportTestCase(test, @"coverage", nil);
        } else if( sCurTestCaseExceptions > 0 ) {
            Log(@"XXX FAILED test case '%s' due to %i exception(s) already reported above",
                test->name,sCurTestCaseExceptions);
            sFailed++;
            RecordFailedTest(test);
            ReportTestCase(test, @"exception", $sprintf(@"%d exception(s) already caught",
                                                        sCurTestCaseExceptions));
        } else {
            Log(@"√√√ %s passed\n\n",test->name);
            test->passed = YES;
            sPassed++;
            ReportTestCase(test, nil, nil);
        }
    }@catch( NSException *x ) {
        if( [x.name isEqualToString: @"TestCaseSkipped"] ) {
            Log(@"... skipping test %s since %@\n\n", test->name, x.reason);
            ReportTestCase(test, @"skipped", x.reason);
        } else {
            fflush(stderr);
            Log(@"XXX FAILED test case '%s' due to:\nException: %@\n%@\n\n", 
                  test->name,x,x.my_callStack);
            sFailed++;
            RecordFailedTest(test);
            NSString* failureType = x.name;
            NSString* reason = x.reason;
            if ([failureType isEqualToString: NSInternalInconsistencyException])
                if ([reason hasPrefix: @"Assertion failed: "]) {
                    failureType = @"assertion";
                    reason = [reason substringFromIndex: 18];
                }
            ReportTestCase(test, failureType, reason);
        }
        // Run after-test blocks to clean up:
        for (void (^block)() in sAfterTestBlocks)
            block();
    }@finally{
        [pool drain];
        test->testptr = NULL;       // prevents test from being run again
    }

    sAfterTestBlocks = savedAfterTestBlocks;
    sCurrentTest = prevTest;
    gRunningTestCase = wasRunningTestCase;
#ifndef MY_DISABLE_LOGGING
    EnableLog(oldLogging);
#endif
    return test->passed;
}


static struct TestCaseLink* FindTestCaseNamed( const char *name ) {
    for( struct TestCaseLink *test = gAllTestCases; test; test=test->next )
        if( strcmp(name,test->name)==0 )
            return test;
    Log(@"... WARNING: Could not find test case named '%s'\n\n",name);
    return NULL;
}


static BOOL RunTestCaseNamed( const char *name )
{
    struct TestCaseLink* test = FindTestCaseNamed(name);
    return test && RunTestCase(test);
}


void _RequireTestCase( const char *name )
{
    struct TestCaseLink* test = FindTestCaseNamed(name);
    if (!test || !test->testptr)
        return;
    if( ! RunTestCase(test) ) {
        [NSException raise: @"TestCaseSkipped" 
                    format: @"prerequisite %s failed", name];
    }
    Log(@"=== Back to test %s ...", sCurrentTest->name);
}


#if XML_REPORT
static void WriteReport(NSString* filename) {
    // See http://stackoverflow.com/a/4925847/98077
    [sReportXML setAttributesWithDictionary: @{@"tests": $sprintf(@"%u", (unsigned)sReportXML.childCount),
                                               @"failures": $sprintf(@"%d", sFailed)}];
    NSXMLDocument* doc = [NSXMLDocument documentWithRootElement: sReportXML];
    doc.documentContentKind = NSXMLDocumentXMLKind;
    doc.characterEncoding = @"UTF-8";
    doc.version = @"1.0";
    doc.standalone = YES;
    NSData* output = [doc XMLDataWithOptions: NSXMLDocumentIncludeContentTypeDeclaration |
                                              NSXMLNodeCompactEmptyElement |
                                              NSXMLNodePrettyPrint];
    [output writeToFile: filename options: NSDataWritingAtomic error: NULL];
}
#endif


void RunTestCases( int argc, const char **argv )
{
    sPassed = sFailed = 0;
    sFailedTestNames = nil;
    BOOL stopAfterTests = NO;
#if XML_REPORT
    sReportXML = [NSXMLElement elementWithName: @"testsuite"];
#endif
    BOOL writeReport = NO;
    for( int i=1; i<argc; i++ ) {
        const char *arg = argv[i];
        if( strncmp(arg,"Test_",5)==0 ) {
            arg += 5;
            if( strcmp(arg,"Only")==0 )
                stopAfterTests = YES;
            else if( strcmp(arg,"Report")==0 )
                writeReport = YES;
            else if( strcmp(arg,"All") == 0 ) {
                for( struct TestCaseLink *link = gAllTestCases; link; link=link->next )
                    RunTestCase(link);
            } else {
                RunTestCaseNamed(arg);
            }
        }
    }
    if (sFailed == 0)
        CheckUncalledCoverage();
    if( sPassed>0 || sFailed>0 || stopAfterTests ) {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        if (writeReport) {
#if XML_REPORT
            WriteReport(@"test_report.xml");
#else
            Warn(@"Write_Report option is not supported on this platform");
#endif
        }
        if( sFailed==0 )
            AlwaysLog(@"√√√√√√ ALL %i TESTS PASSED √√√√√√", sPassed);
        else {
            Warn(@"****** %i of %i TESTS FAILED: %@ ******", 
                 sFailed, sPassed+sFailed,
                 [sFailedTestNames componentsJoinedByString: @", "]);
            exit(1);
        }
        if( stopAfterTests ) {
            Log(@"Stopping after tests ('Test_Only' arg detected)");
            exit(0);
        }
        [pool drain];
    }
    [sFailedTestNames release];
    sFailedTestNames = nil;
#if XML_REPORT
    [sReportXML release];
    sReportXML = nil;
#endif
}


static BOOL RanTestNamed(NSString* testName) {
    struct TestCaseLink* test = FindTestCaseNamed(testName.UTF8String);
    return test && !test->testptr;
}


#pragma mark - TEST COVERAGE:


// Maps test name -> dict([filename, line, teststring] -> int)
static NSMutableDictionary* sCoverageByTest;


// Records the boolean result of a specific Cover() call.
BOOL _Cover(const char *sourceFile, int sourceLine, const char*testName,
            const char *testSource, BOOL whichWay)
{
    if (!gRunningTestCase)
        return whichWay;

    NSString* testKey = @(testName);
    if (!sCoverageByTest)
        sCoverageByTest = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* cases = sCoverageByTest[testKey];
    if (!cases)
        cases = sCoverageByTest[testKey] = [NSMutableDictionary dictionary];

    NSArray* key = @[@(sourceFile), @(sourceLine), @(testSource)];
    int results = [cases[key] intValue];
    if (0 == strcmp(testName, sCurrentTest->name))
        results |= (whichWay ? 2 : 1);      // Bit 0 records a false result, bit 1 records true
    cases[key] = @(results);
    return whichWay;
}

static BOOL CheckCoverage(const char* testName) {
    BOOL ok = YES;
    NSDictionary* cases = sCoverageByTest[@(testName)];
    for (NSArray* key in cases) {
        int results = [cases[key] intValue];
        if (results == 1 || results == 2) {
            Warn(@"Coverage: At %@:%d, only saw (%@) == %s",
                 key[0], [key[1] intValue], key[2], (results==2 ?"YES" : "NO"));
            ok = NO;
        }
    }
    return ok;
}

static BOOL CheckUncalledCoverage(void) {
    if (sCoverageByTest.count == 0)
        return YES;
    Log(@"=== Checking for unreached Cover() calls [UncalledCoverage] ...");

    int failures = 0;
    for (NSString* testName in sCoverageByTest) {
        if (RanTestNamed(testName)) {
            NSDictionary* cases = sCoverageByTest[testName];
            for (NSArray* key in cases) {
                if ([cases[key] intValue] == 0) {
                    Warn(@"Coverage: %@:%d, Cover(%@) unreached by test case %@",
                         key[0], [key[1] intValue], key[2], testName);
                    failures++;
                }
            }
        }
    }

    struct TestCaseLink testCase = {NULL, "UncalledCoverage"};
    if (failures == 0) {
        Log(@"√√√ All reached Cover() calls were reached during their test case\n\n");
        sPassed++;
        ReportTestCase(&testCase, nil, nil);
        return YES;
    } else {
        NSString* message = $sprintf(@"%d Cover() calls were reached, but not during their test case", failures);
        Log(@"XXX %@\n\n", message);
        sFailed++;
        RecordFailedTest(&testCase);
        ReportTestCase(&testCase, @"coverage", message);
        return NO;
    }
}


#endif // MY_ENABLE_TESTS


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
