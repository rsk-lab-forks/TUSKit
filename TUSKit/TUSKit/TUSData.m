//
//  TUSData.m
//  tus-ios-client-demo
//
//  Created by Alexis Hildebrandt on 18-04-2013.
//  Copyright (c) 2013 tus.io. All rights reserved.
//

#import "TUSKit.h"
#import "NSStream+BoundPair.h"

#import "TUSData.h"

#define TUS_BUFSIZE (32*1024)

@interface TUSData ()
@property (assign) long long offset;
@property (strong, nonatomic) NSInputStream* inputStream;
@property (strong, nonatomic) NSOutputStream* outputStream;
@property (strong, nonatomic) NSData* data;
@end

@implementation TUSData

- (id)init
{
    self = [super init];
    if (self) {
        NSInputStream* inStream = nil;
        NSOutputStream* outStream = nil;
        [NSStream createBoundInputStream:&inStream
                            outputStream:&outStream
                              bufferSize:TUS_BUFSIZE];
        assert(inStream != nil);
        assert(outStream != nil);
        self.inputStream = inStream;
        self.outputStream = outStream;
        self.outputStream.delegate = self;
        [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                                     forMode:NSDefaultRunLoopMode];
        [self.outputStream open];
    }
    return self;
}

- (id)initWithData:(NSData*)data
{
    self = [self init];
    if (self) {
        self.data = data;
    }
    return self;
}

#pragma mark - Public Methods
- (NSInputStream*)dataStream
{
    return _inputStream;
}

- (void)stop
{
    [[self outputStream] setDelegate:nil];
    [[self outputStream] removeFromRunLoop:[NSRunLoop currentRunLoop]
                                   forMode:NSDefaultRunLoopMode];
    [[self outputStream] close];
    [self setOutputStream:nil];

    [[self inputStream] setDelegate:nil];
    [[self inputStream] close];
    [self setInputStream:nil];
}

- (long long)length
{
    return _data.length;
}

- (NSUInteger)getBytes:(uint8_t *)buffer
            fromOffset:(long long)offset
                length:(NSUInteger)length
                 error:(NSError **)error
{
    NSRange range = NSMakeRange(offset, length);
    if (offset + length > _data.length) {
        return 0;
    }

    [_data getBytes:buffer range:range];
    return length;
}


#pragma mark - NSStreamDelegate Protocol Methods
- (void)stream:(NSStream *)aStream
   handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
            TUSLog(@"TUSData stream opened");
        } break;
        case NSStreamEventHasSpaceAvailable: {
            uint8_t buffer[TUS_BUFSIZE];
            long long length = TUS_BUFSIZE;
            if (length > [self length] - [self offset]) {
                length = [self length] - [self offset];
            }
            if (!length) {
                [[self outputStream] setDelegate:nil];
                [[self outputStream] close];
                if (self.successBlock) {
                    self.successBlock();
                }
                return;
            }
            TUSLog(@"Reading %lld bytes from %lld to %lld until %lld"
                  , length, [self offset], [self offset] + length, [self length]);
            NSError* error = NULL;
            NSUInteger bytesRead = [self getBytes:buffer
                                       fromOffset:[self offset]
                                           length:length
                                            error:&error];
            if (!bytesRead) {
                TUSLog(@"Unable to read bytes due to: %@", error);
                if (self.failureBlock) {
                    self.failureBlock(error);
                }
            } else {
                NSInteger bytesWritten = [[self outputStream] write:buffer
                                                        maxLength:bytesRead];
                if (bytesWritten <= 0) {
                    TUSLog(@"Network write error %@", [aStream streamError]);
                } else {
                    if (bytesRead != (NSUInteger)bytesWritten) {
                        TUSLog(@"Read %d bytes from buffer but only wrote %d to the network",
                              bytesRead, bytesWritten);
                    }
                    [self setOffset:[self offset] + bytesWritten];
                }
            }
        } break;
        case NSStreamEventErrorOccurred: {
            TUSLog(@"TUSData stream error %@", [aStream streamError]);
            if (self.failureBlock) {
                self.failureBlock([aStream streamError]);
            }
        } break;
        case NSStreamEventHasBytesAvailable:
        case NSStreamEventEndEncountered:
        default:
            assert(NO);     // should never happen for the output stream
            break;
    }
}

@end
