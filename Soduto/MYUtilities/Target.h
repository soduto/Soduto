//
//  Target.h
//  MYUtilities
//
//  Created by Jens Alfke on 2/11/08.
//  Copyright 2008-2013 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface MYTarget : NSObject
{
    id _invocations;    // May be an NSInvocation, or an NSMutableArray of them
}

+ (MYTarget*) targetWithReceiver: (id)receiver action: (SEL)action;

- (void) addTarget: (MYTarget*)target;

- (void) retainTargets;

- (id) invokeWithSender: (id)sender;

@end


#define $target(RCVR,METHOD)    [MYTarget targetWithReceiver: (RCVR) action: @selector(METHOD)]
