//
//  MYData.m
//  MYUtilities
//
//  Created by Jens Alfke on 9/13/13.
//  Copyright (c) 2013 Jens Alfke. All rights reserved.
//

#import "MYData.h"
#import "Test.h"


void* MYEncodeVarUInt(void* buf, UInt64 number) {
    UInt8* dst = buf;
    do {
        UInt8 byte = number & 0x7F;
        number >>= 7;
        if (number != 0)
            byte |= 0x80;
        *dst++ = byte;
    } while (number != 0);
    return dst;
}


const void* MYDecodeVarUInt(const void* buf, const void* bufEnd, UInt64* outNumber) {
    UInt64 result = 0;
    const UInt8* src = buf;
    UInt8 byte;
    unsigned shift = 0;
    while (src < (const UInt8*)bufEnd) {
        byte = *src++;
        result |= (UInt64)(byte & 0x7F) << shift;
        if (!(byte & 0x80)) {
            *outNumber = result;
            return src;
        }
        shift += 7;
    }
    return NULL;
}


size_t MYLengthOfVarUInt(UInt64 number) {
    size_t length = 1;
    while (number >= 0x80) {
        length++;
        number >>= 7;
    }
    return length;
}



@implementation NSData (MYData)

- (MYSlice) my_asSlice {
    return (MYSlice){(void*)self.bytes, self.length};
}

+ (NSData*) my_dataWithSlice: (MYSlice)slice {
    return [self dataWithBytes: slice.bytes length: slice.length];
}

- (const void*) my_readVarUInt: (UInt64*)outNumber at: (const void*)start {
    const void *bytes = self.bytes, *end = bytes+self.length;
    Assert(start >= bytes && start <= end);
    return MYDecodeVarUInt(start, end, outNumber);
}

@end


@implementation NSMutableData (MYData)

- (void) my_appendVarUInt: (UInt64)number {
    UInt8 buf[10];
    UInt8* end = MYEncodeVarUInt(buf, number);
    [self appendBytes: buf length: (end-buf)];
}

@end



MYSlice MYMakeSubSlice(MYSlice slice, size_t offset, size_t length) {
    if (offset > slice.length) {
        offset = slice.length;
        length = 0;
    } else if (offset + length > slice.length) {
        length = slice.length - offset;
    }
    return (MYSlice){slice.bytes + offset, length};
}

BOOL MYSliceReadVarUInt(MYSlice* slice, UInt64* outResult) {
    const void* next = MYDecodeVarUInt(slice->bytes, MYSliceGetEnd(*slice), outResult);
    if (!next)
        return NO;
    MYSliceMoveStartTo(slice, (void*)next);
    return YES;
}

BOOL MYSliceReadSlice(MYSlice* slice, size_t count, MYSlice* outResult) {
    if (count > slice->length)
        return NO;
    *outResult = (MYSlice){slice->bytes, count};
    MYSliceMoveStart(slice, count);
    return YES;
}






TestCase(VarInt) {
    struct {UInt64 number; ptrdiff_t len; UInt8 encoded[12];} tests[] = {
        {0x0000, 1, {0x00}},
        {0x0013, 1, {0x13}},
        {0x007F, 1, {0x7F}},
        {0x0080, 2, {0x80, 0x01}},
        {0x1234, 2, {0xB4, 0x24}},
        {0xFFFF, 3, {0xFF, 0xFF, 0x03}},
        {0x12345678,  5, {0xF8, 0xAC, 0xD1, 0x91, 0x01}},
        {0x123456789, 5, {0x89, 0xCF, 0x95, 0x9A, 0x12}},
        {0x123456787654321, 9, {0xA1, 0x86, 0x95, 0xBB, 0xF8, 0xAC, 0xD1, 0x91, 0x01}},
    };
    UInt8 buf[12];
    for (size_t i=0; i<sizeof(tests)/sizeof(*tests); i++) {
        UInt8* dst = MYEncodeVarUInt(buf, tests[i].number);
        //Log(@"VarInt encoded 0x%llx --> %@", tests[i].number, [NSData dataWithBytes: buf length: dst-buf]);
        CAssertEq(dst-buf, tests[i].len);
        CAssert(memcmp(buf, tests[i].encoded, tests[i].len) == 0);

        UInt64 n;
        const void* end = MYDecodeVarUInt(buf, &buf[12], &n);
        CAssertEq(n, tests[i].number);
        CAssertEq((const UInt8*)end-buf, tests[i].len);
    }
}



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
