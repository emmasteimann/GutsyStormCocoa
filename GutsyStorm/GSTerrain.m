//
//  GSTerrain.m
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSTerrain.h"
#import "GSShader.h"
#import "GSRay.h"

int checkGLErrors(void); // TODO: find a new home for checkGLErrors()

@implementation GSTerrain

- (NSString *)newShaderSourceStringFromFileAt:(NSString *)path
{
    NSError *error;
    NSString *str = [[NSString alloc] initWithContentsOfFile:path
                                                    encoding:NSMacOSRomanStringEncoding
                                                       error:&error];
    if (!str) {
        NSLog(@"Error reading file at %@: %@", path, [error localizedFailureReason]);
        return @"";
    }
    
    return str;
}

- (id)initWithSeed:(unsigned)_seed
            camera:(GSCamera *)_camera
         glContext:(NSOpenGLContext *)_glContext
{
    self = [super init];
    if(self) {
        camera = _camera;
        [camera retain];
        
        assert(checkGLErrors() == 0);
        
        NSString *vertFn = [[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"] pathForResource:@"shader.vert" ofType:@"txt"];
        NSString *fragFn = [[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"] pathForResource:@"shader.frag" ofType:@"txt"];
        
        NSString *vertSrc = [self newShaderSourceStringFromFileAt:vertFn];
        NSString *fragSrc = [self newShaderSourceStringFromFileAt:fragFn];
        
        GSShader *terrainShader = [[GSShader alloc] initWithVertexShaderSource:vertSrc fragmentShaderSource:fragSrc];
        
        [fragSrc release];
        [vertSrc release];
        
        [terrainShader bind];
        [terrainShader bindUniformWithNSString:@"tex" val:0]; // texture unit 0
        
        assert(checkGLErrors() == 0);
        
        textureArray = [[GSTextureArray alloc] initWithImagePath:[[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"]
                                                                  pathForResource:@"terrain"
                                                                  ofType:@"png"]
                                                     numTextures:3];
        
        chunkStore = [[GSChunkStore alloc] initWithSeed:_seed
                                                 camera:_camera
                                          terrainShader:terrainShader
                                              glContext:_glContext];
        
        [terrainShader release];
        
        cursor = [[GSTerrainCursor alloc] init];
        
        maxPlaceDistance = 6.0; // XXX: make this configurable
    }
    return self;
}

- (void)dealloc
{
    [camera release];
    [chunkStore release];
    [textureArray release];
    [cursor release];
    [super dealloc];
}

- (void)draw
{
    static const float edgeOffset = 1e-4;
    glDepthRange(edgeOffset, 1.0); // Use glDepthRange so the block cursor is properly offset from the block itself.
    [textureArray bind];
    [chunkStore drawActiveChunks];
    [textureArray unbind];
    [cursor drawWithEdgeOffset:edgeOffset];
    glDepthRange(0.0, 1.0);
}

- (void)updateWithDeltaTime:(float)dt
        cameraModifiedFlags:(unsigned)cameraModifiedFlags
{
    //Calculate the cursor position.
    if(cameraModifiedFlags) {
        [self recalcCursorPosition];
    }
    
    [chunkStore updateWithDeltaTime:dt cameraModifiedFlags:cameraModifiedFlags];
}

- (void)sync
{
    [chunkStore waitForSaveToFinish];
}

- (void)placeBlockUnderCrosshairs
{
    if(cursor.cursorIsActive) {
        voxel_t block;
        
        bzero(&block, sizeof(voxel_t));
        block.opaque = YES;
        block.dir = VOXEL_DIR_NORTH;
        block.type = VOXEL_TYPE_CUBE;
        
        [chunkStore placeBlockAtPoint:cursor.cursorPlacePos block:block];
        [self recalcCursorPosition];
    }
}

- (void)removeBlockUnderCrosshairs
{
    if(cursor.cursorIsActive) {
        voxel_t block;
        
        bzero(&block, sizeof(voxel_t));
        block.dir = VOXEL_DIR_NORTH;
        block.type = VOXEL_TYPE_EMPTY;
        
        [chunkStore placeBlockAtPoint:cursor.cursorPos block:block];
        [self recalcCursorPosition];
    }
}

- (void)recalcCursorPosition
{
    GSRay ray = GSRay_Make(camera.cameraEye, GLKQuaternionRotateVector3(camera.cameraRot, GLKVector3Make(0, 0, -1)));
    __block BOOL cursorIsActive = NO;
    __block GLKVector3 prev = ray.origin;
    __block GLKVector3 cursorPos;
    
    [chunkStore enumerateVoxelsOnRay:ray maxDepth:maxPlaceDistance withBlock:^(GLKVector3 p, BOOL *stop, BOOL *fail) {
        voxel_t voxel;

        if(![chunkStore tryToGetVoxelAtPoint:p voxel:&voxel]) {
            *fail = YES; // Stops enumerations with un-successful condition
        }
        
        if(voxel.type != VOXEL_TYPE_EMPTY) {
            cursorIsActive = YES;
            cursorPos = p;
            *stop = YES; // Stops enumeration with successful condition.
        } else {
            prev = p;
        }
    }];

    cursor.cursorIsActive = cursorIsActive;
    cursor.cursorPos = cursorPos;
    cursor.cursorPlacePos = prev;
}

@end
