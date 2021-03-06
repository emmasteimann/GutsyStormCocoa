//
//  GSReaderWriterLock.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/23/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

@interface GSReaderWriterLock : NSObject

- (BOOL)tryLockForReading;
- (void)lockForReading;
- (void)unlockForReading;

- (BOOL)tryLockForWriting;
- (void)lockForWriting;
- (void)unlockForWriting;

@end
