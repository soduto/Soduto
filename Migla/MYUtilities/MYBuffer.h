//
//  MYBuffer.h
//  MYUtilities
//
//  Created by Jens Alfke on 4/5/15.
//  Copyright (c) 2015 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MYData.h"


@protocol MYWriter <NSObject>

- (BOOL) writeData: (NSData*)data;
- (BOOL) writeSlice: (MYSlice)slice;

/** Adds the contents of the stream. The stream must already be open. This may not read from the
    stream right way; instead the writer may keep a reference to the stream and only read from
    it on demand to satisfy its own read requests. For this reason you shouldn't read from or close
    the stream after this call! The MYWriter instance will close the stream when it's been entirely
    read, or when the writer itself is dealloced. */
- (BOOL) writeContentsOfStream: (NSInputStream*)inputStream;

@end


@protocol MYReader <NSObject>

- (ssize_t) readBytes: (void*)buffer maxLength: (size_t)maxLength;

/** If possible, returns a slice (pointer+length) pointing to the reader data read from the
    buffer. This memory is only valid until the next call to the buffer; do NOT free or modify it.
    You may get back fewer bytes than you asked for; that doesn't mean that the buffer is at EOF.
    This may well fail (if reading from a stream) in which case the slice points to NULL. In that
    case you should fall back to the regular -readBytes:maxLength: call. */
- (MYSlice) readSliceOfMaxLength: (size_t)maxLength;

@property (readonly) BOOL hasBytesAvailable;
@property (readonly) BOOL atEnd;

@end


/** A growable data buffer that can be written/appended to, and read from.
    A stream can be added to a buffer; this effectively adds its entire contents, but they'll be
    read on demand instead of being copied into memory all at once. */
@interface MYBuffer : NSObject <MYReader, MYWriter>

- (instancetype) initWithData: (NSData*)data;

@property (readonly) NSUInteger minLength;
@property (readonly) NSUInteger maxLength;

/** Returns the entire (remaining) contents of the buffer as a single NSData.
    This doesn't consume any bytes, it just reorganizes the buffer's contents if needed. */
- (NSData*) flattened;

//- (ssize_t) unReadBytes: (void*)buffer maxLength: (size_t)maxLength;

@end
