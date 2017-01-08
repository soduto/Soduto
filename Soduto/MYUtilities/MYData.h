//
//  MYData.h
//  MYUtilities
//
//  Created by Jens Alfke on 9/13/13.
//  Copyright (c) 2013 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>

/** Encodes an unsigned integer of up to 64 bits as a varint.
    The buffer must be large enough to hold the varint; 10 bytes is always sufficient.
    See https://developers.google.com/protocol-buffers/docs/encoding#varints */
void* MYEncodeVarUInt(void* buf, UInt64 number);

/** Decodes a varint from a buffer. Returns a pointer to the byte past the end of the varint,
    or NULL on failure. */
const void* MYDecodeVarUInt(const void* buf, const void* bufEnd, UInt64* outNumber);

/** Returns the number of bytes of the varint encoding of the number. */
size_t MYLengthOfVarUInt(UInt64 number);


/** A slice represents a range of addresses, without owning them. */
typedef struct {
    const void* bytes;
    size_t length;
} MYSlice;

static inline MYSlice MYMakeSlice(const void* bytes, size_t length)
    {return (MYSlice){bytes, length};}
static inline MYSlice MYNullSlice()
    {return (MYSlice){NULL, 0};}
MYSlice MYMakeSubSlice(MYSlice slice, size_t offset, size_t length);
static inline BOOL MYSliceIsEmpty(MYSlice slice)
    {return slice.length == 0;}
static inline const void* MYSliceGetEnd(MYSlice slice)
    {return slice.bytes + slice.length;}
static inline void MYSliceMoveStart(MYSlice *slice, size_t n)
    {slice->bytes += n; slice->length -= n;}
static inline void MYSliceMoveStartTo(MYSlice *slice, const void* start)
    {slice->length -= start - slice->bytes; slice->bytes = start;}

BOOL MYSliceReadVarUInt(MYSlice* slice, UInt64* outResult);
BOOL MYSliceReadSlice(MYSlice* slice, size_t count, MYSlice* outResult);


@interface NSData (MYData)
+ (instancetype) my_dataWithSlice: (MYSlice)slice;
- (MYSlice) my_asSlice;
- (const void*) my_readVarUInt: (UInt64*)number at: (const void*)start;
@end


@interface NSMutableData (MYData)
- (void) my_appendVarUInt: (UInt64)number;
@end
