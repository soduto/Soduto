//
//  Target.m
//  MYUtilities
//
//  Created by Jens Alfke on 2/11/08.
//  Copyright 2008-2013 Jens Alfke. All rights reserved.
//

#import "Target.h"
#import "Logging.h"
#import "Test.h"


@implementation MYTarget


- (id) initWithReceiver: (id)receiver action: (SEL)action
{
    self = [super init];
    if( self ) {
        NSMethodSignature *sig = [receiver methodSignatureForSelector: action];
        CAssert(sig,@"%@<%p> does not respond to %@",[receiver class],receiver,NSStringFromSelector(action));
        CAssert(sig.numberOfArguments==3,
               @"-[%@ %@] can't be used as a target because it takes >1 param",
               [receiver class],NSStringFromSelector(action));
        CAssert(0==strcmp([sig getArgumentTypeAtIndex: 2],"@"),
               @"-[%@ %@] can't be used as a target because it takes a non-object param",
               [receiver class],NSStringFromSelector(action));
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature: sig];
        inv.target = receiver;
        inv.selector = action;
        _invocations = [inv retain];
    }
    return self;
}

+ (MYTarget*) targetWithReceiver: (id)receiver action: (SEL)action
{
    return [[[self alloc] initWithReceiver: receiver action: action] autorelease];
}

- (void) dealloc
{
    [_invocations release];
    [super dealloc];
}


- (NSArray*) invocations
{
    NSMutableArray *invocations = $castIf(NSMutableArray,_invocations);
    if( ! invocations )
        invocations = [NSMutableArray arrayWithObject: _invocations];
    return invocations;
}


- (NSString*) description
{
    NSMutableString *desc = [NSMutableString stringWithFormat: @"%@{", self.class];
    BOOL first = YES;
    for( NSInvocation *inv in self.invocations ) {
        if( first )
            first = NO;
        else
            [desc appendString: @", "];
        [desc appendFormat: @"-[%@ %@]", [inv.target class], NSStringFromSelector(inv.selector)];
    }
    [desc appendString: @"}"];
    return desc;
}


static BOOL equalInvocations( NSInvocation *a, NSInvocation *b )
{
    return a.target==b.target && a.selector==b.selector;
}


- (BOOL) isEqual: (MYTarget*)t
{
    if( ! [t isKindOfClass: [self class]] )
        return NO;
    if( [_invocations isKindOfClass: [NSInvocation class]] && [t->_invocations isKindOfClass: [NSInvocation class]] )
        return equalInvocations(_invocations,t->_invocations);
    NSArray *myInvocations = self.invocations, *itsInvocations = t.invocations;
    NSUInteger n = myInvocations.count;
    if( n != itsInvocations.count )
        return NO;
    for( NSUInteger i=0; i<n; i++ )
        if( ! equalInvocations( [myInvocations objectAtIndex: i],
                                [itsInvocations objectAtIndex: i] ) )
            return NO;
    return YES;
}


- (void) retainTargets
{
    NSMutableArray *invocations = $castIf(NSMutableArray,_invocations);
    if( invocations ) {
        for( NSInvocation *invocation in invocations )
            [invocation retainArguments];
    } else {
        [_invocations retainArguments];
    }
}


- (void) addTarget: (MYTarget*)target
{
    setObj(&_invocations,[self invocations]);
    [_invocations addObjectsFromArray: target.invocations];
}


static id invokeSingleTarget( NSInvocation *invocation, id param )
{
    id result = nil;
    if( invocation && invocation.target ) {
        [invocation retain];
        @try{
            [invocation setArgument: &param atIndex: 2];
            [invocation invoke];
            
            NSMethodSignature *sig = invocation.methodSignature;
            NSUInteger returnLength = sig.methodReturnLength;
            if( returnLength==0 ) {
                result = nil; // void
            } else {
                const char *returnType = sig.methodReturnType;
                if( returnType[0]=='@' ) {
                    [invocation getReturnValue: &result];
                } else {
                    UInt8 returnBuffer[returnLength];
                    [invocation getReturnValue: &returnBuffer];
                    result = [NSValue valueWithBytes: &returnBuffer objCType: returnType];
                }
            }
        }@finally{
            [invocation release];
        }
    }
    return result;
}


- (id) invokeWithSender: (id)sender
{
    id result;
    NSMutableArray *invocations = $castIf(NSMutableArray,_invocations);
    if( invocations ) {
        result = nil;
        for( NSInvocation *invocation in invocations )
            result = invokeSingleTarget(invocation,sender);
    } else {
        result = invokeSingleTarget(_invocations,sender);
    }
    return result;
}


@end


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
