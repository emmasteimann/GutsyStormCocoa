//
//  GSByteBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import "GSByteBuffer.h"
#import "Chunk.h"
#import "GutsyStormErrorCodes.h"
#import "SyscallWrappers.h"

#import <GLKit/GLKQuaternion.h> // used by Voxel.h
#import "Voxel.h" // for INDEX_BOX


static void samplingPoints(size_t count, GLKVector3 *sample, GSIntegerVector3 normal);


@implementation GSByteBuffer

+ (void)newBufferFromFile:(NSURL *)url
               dimensions:(GSIntegerVector3)dimensions
                    queue:(dispatch_queue_t)queue
        completionHandler:(void (^)(GSByteBuffer *aBuffer, NSError *error))completionHandler
{
    // If the file does not exist then do nothing.
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        NSString *reason = [NSString stringWithFormat:@"File not found for buffer: %@", url];
        completionHandler(nil, [NSError errorWithDomain:GSErrorDomain
                                                   code:GSFileNotFoundError
                                               userInfo:@{NSLocalizedFailureReasonErrorKey:reason}]);
        return;
    }

    const int fd = Open(url, O_RDONLY, 0);
    const size_t len = BUFFER_SIZE_IN_BYTES(dimensions);

    dispatch_read(fd, len, queue, ^(dispatch_data_t dd, int error) {
        Close(fd);

        if(error) {
            char errorMsg[LINE_MAX];
            strerror_r(-error, errorMsg, LINE_MAX);
            NSString *reason = [NSString stringWithFormat:@"error with read(fd=%d): %s [%d]", fd, errorMsg, error];
            completionHandler(nil, [NSError errorWithDomain:NSPOSIXErrorDomain
                                                       code:error
                                                   userInfo:@{NSLocalizedFailureReasonErrorKey:reason}]);
            return;
        }

        if(dispatch_data_get_size(dd) != len) {
            NSString *reason = [NSString stringWithFormat:@"Read %zu bytes from file, but expected %zu bytes.",
                                dispatch_data_get_size(dd), len];
            completionHandler(nil, [NSError errorWithDomain:GSErrorDomain
                                                       code:GSInvalidChunkDataOnDiskError
                                                   userInfo:@{NSLocalizedFailureReasonErrorKey:reason}]);
            return;
        }

        // Map the data object to a buffer in memory and use it to initialize a new GSByteBuffer object.
        size_t size = 0;
        const void *buffer = NULL;
        dispatch_data_t mappedData = dispatch_data_create_map(dd, &buffer, &size);
        assert(len == size);
        GSByteBuffer *aBuffer = [[self alloc] initWithDimensions:dimensions data:(const buffer_element_t *)buffer];
        dispatch_release(mappedData);
        completionHandler(aBuffer, nil);
    });
}

+ (id)newBufferFromLargerRawBuffer:(uint8_t *)srcBuf
                           srcMinP:(GSIntegerVector3)combinedMinP
                           srcMaxP:(GSIntegerVector3)combinedMaxP
{
    static const GSIntegerVector3 dimensions = {CHUNK_SIZE_X+2, CHUNK_SIZE_Y, CHUNK_SIZE_Z+2};
    
    _Static_assert(sizeof(srcBuf[0]) == sizeof(buffer_element_t), "copyLargeBufferIntoSmallBuffer expects uint8_t buffers");
    assert(srcBuf);
    assert(dstBuf);
    assert(combinedMaxP.y - combinedMinP.y == CHUNK_SIZE_Y);

    GSIntegerVector3 offset = GSIntegerVector3_Make(1, 0, 1);
    GSIntegerVector3 a = GSIntegerVector3_Make(-1, 0, -1);
    GSIntegerVector3 b = GSIntegerVector3_Make(CHUNK_SIZE_X+1, 0, CHUNK_SIZE_Z+1);
    GSIntegerVector3 p; // loop counter

    void *dstBuf = malloc(BUFFER_SIZE_IN_BYTES(dimensions));

    FOR_Y_COLUMN_IN_BOX(p, a, b)
    {
        size_t srcOffset = INDEX_BOX(p, combinedMinP, combinedMaxP);
        size_t dstOffset = INDEX_BOX(GSIntegerVector3_Add(p, offset), ivecZero, dimensions);
        memcpy(dstBuf + dstOffset, srcBuf + srcOffset, CHUNK_SIZE_Y * sizeof(buffer_element_t));
    }

    id aBuffer = [[self alloc] initWithDimensions:dimensions data:dstBuf];

    free(dstBuf);

    return aBuffer;
}

- (id)initWithDimensions:(GSIntegerVector3)dim
{
    self = [super init];
    if (self) {
        assert(dim.x >= CHUNK_SIZE_X);
        assert(dim.y >= CHUNK_SIZE_Y);
        assert(dim.z >= CHUNK_SIZE_Z);

        _dimensions = dim;

        _offsetFromChunkLocalSpace = GSIntegerVector3_Make((dim.x - CHUNK_SIZE_X) / 2,
                                                           (dim.y - CHUNK_SIZE_Y) / 2,
                                                           (dim.z - CHUNK_SIZE_Z) / 2);

        _data = malloc(BUFFER_SIZE_IN_BYTES(dim));

        if(!_data) {
            [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for lighting buffer."];
        }

        bzero(_data, BUFFER_SIZE_IN_BYTES(dim));
    }
    
    return self;
}

- (id)initWithDimensions:(GSIntegerVector3)dim data:(const buffer_element_t *)data
{
    assert(data);
    self = [self initWithDimensions:dim];
    if (self) {
        memcpy(_data, data, BUFFER_SIZE_IN_BYTES(dim));
    }

    return self;
}

- (void)dealloc
{
    free(_data);
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[GSByteBuffer allocWithZone:zone] initWithDimensions:_dimensions data:_data];
}

- (buffer_element_t)valueAtPoint:(GSIntegerVector3)chunkLocalPos
{
    assert(_data);

    GSIntegerVector3 dim = self.dimensions;
    GSIntegerVector3 p = GSIntegerVector3_Add(chunkLocalPos, _offsetFromChunkLocalSpace);

    if(p.x >= 0 && p.x < dim.x &&
       p.y >= 0 && p.y < dim.y &&
       p.z >= 0 && p.z < dim.z) {
        return _data[INDEX_INTO_LIGHTING_BUFFER(dim, p)];
    } else {
        return 0;
    }
}

- (buffer_element_t)lightForVertexAtPoint:(GLKVector3)vertexPosInWorldSpace
                               withNormal:(GSIntegerVector3)normal
                                     minP:(GLKVector3)minP
{
    static const size_t count = 4;
    GLKVector3 sample[count];
    float light;
    int i;

    assert(_data);

    samplingPoints(count, sample, normal);

    for(light = 0.0f, i = 0; i < count; ++i)
    {
        GSIntegerVector3 clp = GSIntegerVector3_Make(truncf(sample[i].x + vertexPosInWorldSpace.x - minP.x),
                                                     truncf(sample[i].y + vertexPosInWorldSpace.y - minP.y),
                                                     truncf(sample[i].z + vertexPosInWorldSpace.z - minP.z));

        assert(clp.x >= -1 && clp.x <= CHUNK_SIZE_X);
        assert(clp.y >= -1 && clp.y <= CHUNK_SIZE_Y);
        assert(clp.z >= -1 && clp.z <= CHUNK_SIZE_Z);

        light += [self valueAtPoint:clp] / (float)count;
    }
    
    return light;
}

- (void)saveToFile:(NSURL *)url queue:(dispatch_queue_t)queue group:(dispatch_group_t)group
{
    dispatch_group_enter(group);

    dispatch_data_t dd = dispatch_data_create(_data, BUFFER_SIZE_IN_BYTES(self.dimensions),
                                                    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                                    DISPATCH_DATA_DESTRUCTOR_DEFAULT);

    dispatch_async(queue, ^{
        int fd = Open(url, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);

        dispatch_write(fd, dd, queue, ^(dispatch_data_t data, int error) {
            Close(fd);

            if(error) {
                raiseExceptionForPOSIXError(error, [NSString stringWithFormat:@"error with write(fd=%u)", fd]);
            }

            dispatch_release(dd);
            dispatch_group_leave(group);
        });
    });
}

@end


static void samplingPoints(size_t count, GLKVector3 *sample, GSIntegerVector3 n)
{
    assert(count == 4);
    assert(sample);

    const float a = 0.5f;

    if(n.x==1 && n.y==0 && n.z==0) {
        sample[0] = GLKVector3Make(+a, -a, -a);
        sample[1] = GLKVector3Make(+a, -a, +a);
        sample[2] = GLKVector3Make(+a, +a, -a);
        sample[3] = GLKVector3Make(+a, +a, +a);
    } else if(n.x==-1 && n.y==0 && n.z==0) {
        sample[0] = GLKVector3Make(-a, -a, -a);
        sample[1] = GLKVector3Make(-a, -a, +a);
        sample[2] = GLKVector3Make(-a, +a, -a);
        sample[3] = GLKVector3Make(-a, +a, +a);
    } else if(n.x==0 && n.y==1 && n.z==0) {
        sample[0] = GLKVector3Make(-a, +a, -a);
        sample[1] = GLKVector3Make(-a, +a, +a);
        sample[2] = GLKVector3Make(+a, +a, -a);
        sample[3] = GLKVector3Make(+a, +a, +a);
    } else if(n.x==0 && n.y==-1 && n.z==0) {
        sample[0] = GLKVector3Make(-a, -a, -a);
        sample[1] = GLKVector3Make(-a, -a, +a);
        sample[2] = GLKVector3Make(+a, -a, -a);
        sample[3] = GLKVector3Make(+a, -a, +a);
    } else if(n.x==0 && n.y==0 && n.z==1) {
        sample[0] = GLKVector3Make(-a, -a, +a);
        sample[1] = GLKVector3Make(-a, +a, +a);
        sample[2] = GLKVector3Make(+a, -a, +a);
        sample[3] = GLKVector3Make(+a, +a, +a);
    } else if(n.x==0 && n.y==0 && n.z==-1) {
        sample[0] = GLKVector3Make(-a, -a, -a);
        sample[1] = GLKVector3Make(-a, +a, -a);
        sample[2] = GLKVector3Make(+a, -a, -a);
        sample[3] = GLKVector3Make(+a, +a, -a);
    } else {
        assert(!"shouldn't get here");
        sample[0] = GLKVector3Make(0, 0, 0);
        sample[1] = GLKVector3Make(0, 0, 0);
        sample[2] = GLKVector3Make(0, 0, 0);
        sample[3] = GLKVector3Make(0, 0, 0);
    }
}