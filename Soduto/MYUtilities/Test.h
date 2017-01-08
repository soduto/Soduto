//
//  Test.h
//  MYUtilities
//
//  Created by Jens Alfke on 1/5/08.
//  Copyright 2008-2013 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CollectionUtils.h"

#ifndef MY_ENABLE_TESTS
#define MY_ENABLE_TESTS 0
#endif


/** Call this first thing in main() to run tests.
    This function is a no-op if the DEBUG macro is not defined (i.e. in a release build).
    At runtime, to cause a particular test "X" to run, add a command-line argument "Test_X".
    To run all tests, add the argument "Test_All".
    To run only tests without starting the main program, add the argument "Test_Only".
    To generate a JUnit-compatible XML report file "test_report.xml", add "Test_Report. */
#if MY_ENABLE_TESTS
void RunTestCases( int argc, const char **argv );
extern BOOL gRunningTestCase;
#else
#define RunTestCases(ARGC,ARGV)
#define gRunningTestCase NO
#endif

/** The TestCase() macro declares a test case.
    Its argument is a name for the test case (without quotes), and it's followed with a block
    of code implementing the test.
    The code should raise an exception if anything fails.
    The CAssert, CAssertEqual and CAssertEq macros, below, are the most useful way to do this.
    A test case can register a dependency on another test case by calling RequireTestCase().
    Example:
        TestCase(MyLib) {
            RequireTestCase("LibIDependOn");
            CAssertEq( myFunction(), 12345 );
        }
    Test cases are disabled if the MY_ENABLE_TESTS macro is not defined (i.e. in a release build). */
#if MY_ENABLE_TESTS
#define TestCase(NAME)      void Test_##NAME(void); \
                            struct TestCaseLink linkToTest##NAME = {&Test_##NAME,#NAME}; \
                            __attribute__((constructor)) static void registerTestCase##NAME() \
                                {linkToTest##NAME.next = gAllTestCases; gAllTestCases=&linkToTest##NAME; } \
                            void Test_##NAME(void)
#else
#define TestCase(NAME)      __attribute__((unused)) static void Test_##NAME(void)
#endif

/** Can call this in a test case to indicate a prerequisite.
    The prerequisite test will be run first, and if it fails, the current test case will be skipped. */
#if MY_ENABLE_TESTS
#define RequireTestCase(NAME)   _RequireTestCase(#NAME)
void _RequireTestCase( const char *name );
#else
#define RequireTestCase(NAME)
#endif


#if MY_ENABLE_TESTS
/** Schedules a block to run after the currently-running test case completes.
    This is useful for cleanup of resources created during a test.
    If this function is called multiple times, the blocks will be invoked in reverse order. */
void AfterThisTest(void (^block)());
#endif

/** General-purpose assertions, replacing NSAssert etc.. You can use these outside test cases. */

#ifndef MY_BLOCK_ASSERTS

#define Assert(COND,MSG...)    do{ if( __builtin_expect(!(COND),NO) ) { \
                                    _AssertFailed(__func__, __FILE__, __LINE__,\
                                                        #COND,##MSG,NULL); } }while(0)

// AssertEqual is for Obj-C objects
#define AssertEqual(VAL,EXPECTED)   _AssertEqual((VAL),(EXPECTED), #VAL, __func__, __FILE__, __LINE__)

// AssertEq is for scalars (int, float...)
#define AssertEq(VAL,EXPECTED)  do{ __typeof(VAL) _val = VAL; __typeof(EXPECTED) _expected = EXPECTED;\
                                    Assert(_val==_expected, @"Unexpected value for %s: %@ (expected %@)", #VAL,$object(_val),$object(_expected)); \
                                }while(0)
#define AssertAlmostEq(N1,N2, TOL) CAssert(fabs((N1) - (N2)) < (TOL), \
@"Got %.9f, expected %.9f", (N1), (N2));

#define AssertNil(VAL)          AssertEq((VAL),(id)nil)
#define AssertNull(VAL)         AssertEq((VAL),NULL)

#else // MY_BLOCK_ASSERTS
#define Assert(COND,MSG...)         do{ }while(0)
#define AssertEqual(VAL,EXPECTED)   do{ }while(0)
#define AssertEq(VAL,EXPECTED)      do{ }while(0)
#define AssertAlmostEq(N1,N2, TOL)  do{ }while(0)
#define AssertNil(VAL)              do{ }while(0)
#define AssertNull(VAL)             do{ }while(0)
#endif

#define AssertAbstractMethod()  _AssertAbstractMethodFailed(self,_cmd);

// DAssert variants are suppressed in Release builds, for use in performance-sensitive code
#if DEBUG
#define DAssert         Assert
#define DAssertEqual    AssertEqual
#define DAssertEq       AssertEq
#define DAssertNil      AssertNil
#define DAssertNull     AssertNull
#else
#define DAssert(COND,MSG...)         do{ }while(0)
#define DAssertEqual(VAL,EXPECTED)   do{ }while(0)
#define DAssertEq(VAL,EXPECTED)      do{ }while(0)
#define DAssertAlmostEq(N1,N2, TOL)  do{ }while(0)
#define DAssertNil(VAL)              do{ }while(0)
#define DAssertNull(VAL)             do{ }while(0)
#endif

// These were for use in functions; not necessary anymore
#define CAssert Assert
#define CAssertEqual AssertEqual
#define CAssertEq AssertEq
#define CAssertNil AssertNil
#define CAssertNull AssertNull


// Returns a string summarizing why a and b are not equal; or nil if they are equal.
// Descends into NSArrays and NSDictionaries to identify mismatched items.
// Considers NSNumbers equal if the difference is small enough to be rounding error.
NSString* WhyUnequalObjects(id a, id b);


/** Simple test-coverage helpers:
    The Cover() macro verifies that both sides of an if(), or the body of a while(),
    are exercised during a test. Just wrap Cover(...) around the condition being tested,
    and during testing a warning will be logged if that instance of Cover() is called with
    only a true or only a false value. (Unfortunately it can't detect if the Cover() call
    isn't reached at all.)
    In order for this to work you need to add a TestedBy(TestName) call at the start of the
    function/method, where TestName is the name of the TestCase function that should be
    providing the code coverage.
    Example:
        - (void) foo {
            TestedBy(FooTest);
            if (Cover(someCondition())) { ... } else { ... }
        }
    After FooTest completes, a warning will be logged if someCondition() was only true or only
    false during that Cover call.
 
    To make this less obtrusive, you might want to do something like
        #define ifc(COND) if(Cover(COND))
*/

#if MY_ENABLE_TESTS
#define TestedBy(TEST_NAME) static const char* __unused kTestedBy = #TEST_NAME; \
            extern void Test_##TEST_NAME(void); __unused void* x = &Test_##TEST_NAME
#define Cover(CONDITION) ({ \
    BOOL _b=!!(CONDITION); \
    if (__builtin_expect(gRunningTestCase,NO)) \
        _Cover(__FILE__, __LINE__, kTestedBy, #CONDITION, _b); \
    _b;})
#else
#define TestedBy(TEST_NAME)
#define Cover(CONDITION) (CONDITION)
#endif


// Nasty internals ...
#if MY_ENABLE_TESTS
void _RunTestCase( void (*testptr)(), const char *name );

struct TestCaseLink {void (*testptr)(); const char *name; BOOL passed; struct TestCaseLink *next;};
extern struct TestCaseLink *gAllTestCases;
#endif // MY_ENABLE_TESTS
void _AssertEqual(id val, id expected, const char* valExpr,
                  const char* selOrFn, const char* sourceFile, int sourceLine);
void _AssertFailed(const void *selOrFn, const char *sourceFile, int sourceLine,
                   const char *condString, NSString *message, ... ) __attribute__((noreturn));
void _AssertAbstractMethodFailed( id rcvr, SEL cmd) __attribute__((noreturn));
BOOL _Cover(const char *sourceFile, int sourceLine, const char*testName, const char *testSource, BOOL whichWay);
