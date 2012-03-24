//
//  GSChunk.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>

#import "GSVector3.h"

#define CHUNK_SIZE_X (128)
#define CHUNK_SIZE_Y (64)
#define CHUNK_SIZE_Z (128)


@interface GSChunk : NSObject
{
    GLuint vboChunkVerts, vboChunkNorms, vboChunkTexCoords;
    GLsizei numElementsInVBO; // This is numChunkVerts*3, but use a copy so we won't have to lock geometry to get it.
    
    NSConditionLock *lockGeometry;
    GLsizei numChunkVerts;
    GLfloat *vertsBuffer;
    GLfloat *normsBuffer;
    GLfloat *texCoordsBuffer;
    
    NSConditionLock *lockVoxelData;
    BOOL *voxelData;
}

@property (readonly, nonatomic) GSVector3 minP;
@property (readonly, nonatomic) GSVector3 maxP;

- (id)initWithSeed:(unsigned)seed
              minP:(GSVector3)minP
              maxP:(GSVector3)maxP
     terrainHeight:(float)terrainHeight;
- (void)draw;

@end
