//
//  MYStreamUtils.m
//  MYUtilities
//
//  Created by Jens Alfke on 7/25/12.
//  Copyright (c) 2012 Jens Alfke. All rights reserved.
//

#import "MYStreamUtils.h"

#define kReadBufferSize 32768


@implementation NSInputStream (MYUtils)


- (BOOL) my_readBytes: (void(^)(const void* bytes, NSUInteger length))block {
    uint8_t* buffer;
    NSUInteger bufferLen;
    if ([self getBuffer: &buffer length: &bufferLen]) {
        block(buffer, bufferLen);
        return YES;
    } else {
        buffer = malloc(kReadBufferSize);
        if (!buffer)
            return NO;
        NSInteger bytesRead = [self read: buffer maxLength: kReadBufferSize];
        BOOL success = bytesRead >= 0;
        if (success)
            block(buffer, bytesRead);
        free(buffer);
        return success;
    }
}


- (BOOL) my_readData: (void(^)(NSData* data))block {
    return [self my_readBytes: ^(const void *bytes, NSUInteger length) {
        NSData* data = [[NSData alloc] initWithBytesNoCopy: (void*)bytes length: length
                                              freeWhenDone: NO];
        block(data);
    }];
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
