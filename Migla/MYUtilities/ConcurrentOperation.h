//
//  ConcurrentOperation.h
//  MYUtilities
//
//  Created by Jens Alfke on 2/5/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface ConcurrentOperation : NSOperation 
{
    BOOL _isExecuting, _isFinished;
}

- (void) finish;

@end
