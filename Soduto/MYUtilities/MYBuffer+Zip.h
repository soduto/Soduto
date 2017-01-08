//
//  MYBuffer+Zip.h
//  MYUtilities
//
//  Created by Jens Alfke on 4/26/15.
//  Copyright (c) 2015 Jens Alfke. All rights reserved.
//

#import "MYBuffer.h"


/** Wraps a MYReader and transparently compresses or decompresses the data being read from it. */
@interface MYZipReader : NSObject <MYReader>
- (instancetype) initWithReader: (id<MYReader>)reader
                    compressing: (BOOL)compressing;
@end


/** Wraps a MYWriter and transparently compresses or decompresses the data being written to it.
    Note: If compressing, then after the last data is written you have to issue an additional
    zero-byte write to flush the zlib compressor and write the last of the compressed data to the
    original writer. */
@interface MYZipWriter : NSObject <MYWriter>
- (instancetype) initWithWriter: (id<MYWriter>)writer
                    compressing: (BOOL)compressing;
@end
