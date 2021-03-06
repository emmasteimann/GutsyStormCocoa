//
//  GSVBOHolder.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import "GSVBOHolder.h"


static void syncDestroySingleVBO(NSOpenGLContext *context, GLuint vbo);


@implementation GSVBOHolder
{
    NSOpenGLContext *_glContext;
}

- (id)initWithHandle:(GLuint)handle context:(NSOpenGLContext *)context
{
    if(self = [super init]) {
#ifdef NDEBUG
        assert(context);
        assert(handle);
        [context makeCurrentContext];
        CGLLockContext((CGLContextObj)[context CGLContextObj]);
        assert(glIsBuffer(handle));
        CGLUnlockContext((CGLContextObj)[context CGLContextObj]);
#endif

        _glContext = context;
        _handle = handle;
    }
    return self;
}

- (void)dealloc
{
    NSOpenGLContext *context = _glContext;
    GLuint handle = _handle;

    assert(context);

    dispatch_async(dispatch_get_main_queue(), ^{
        syncDestroySingleVBO(context, handle);
    });
}

@end


static void syncDestroySingleVBO(NSOpenGLContext *context, GLuint vbo)
{
    assert(context);
    if(vbo) {
        [context makeCurrentContext];
        CGLLockContext((CGLContextObj)[context CGLContextObj]); // protect against display link thread
        glDeleteBuffers(1, &vbo);
        CGLUnlockContext((CGLContextObj)[context CGLContextObj]);
    }
}