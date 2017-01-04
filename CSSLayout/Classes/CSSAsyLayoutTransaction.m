//
//  CSSAsyLayoutTransaction.m
//  CSJSView
//
//  Created by 沈强 on 2016/8/31.
//  Copyright © 2016年 沈强. All rights reserved.
//

#import "CSSAsyLayoutTransaction.h"
#import <objc/message.h>
#include <libkern/OSSpinLockDeprecated.h>

static NSMutableArray *messageQueue = nil;

static CFRunLoopSourceRef _runLoopSource = nil;

static dispatch_queue_t calculate_creation_queue() {
  static dispatch_queue_t calculate_creation_queue;
  static dispatch_once_t creationOnceToken;
  dispatch_once(&creationOnceToken, ^{
    calculate_creation_queue = dispatch_queue_create("flexbox.calculateLayout", DISPATCH_QUEUE_SERIAL);
  });
  
  return calculate_creation_queue;
}

static void display_Locked(dispatch_block_t block) {
  static OSSpinLock display_lock = OS_SPINLOCK_INIT;
  OSSpinLockLock(&display_lock);
  block();
  OSSpinLockUnlock(&display_lock);
}


static void enqueue(dispatch_block_t block) {
  display_Locked(^() {
    if (!messageQueue) {
      messageQueue = [NSMutableArray array];
    }
    [messageQueue addObject:block];
    CFRunLoopSourceSignal(_runLoopSource);
    CFRunLoopWakeUp(CFRunLoopGetMain());
  });
}

static void processQueue() {
  display_Locked(^{
    for (dispatch_block_t block in messageQueue) {
      block();
    }
    [messageQueue removeAllObjects];
  });
}


static void calculate_create_task_safely(dispatch_block_t block, dispatch_block_t complete) {
  dispatch_async(calculate_creation_queue(), ^ {
    block();
    enqueue(complete);
  });
}

static void sourceContextCallBackLog(void *info) {
  
#if DEBUG
  
  NSLog(@"applay CSS layout");
  
#endif
  
}


static void _messageGroupRunLoopObserverCallback(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
  
  processQueue();
  
}


@implementation CSSAsyLayoutTransaction

+ (void)load {
  
  CFRunLoopObserverRef observer;
  
  CFRunLoopRef runLoop = CFRunLoopGetMain();
  
  CFOptionFlags activities = (kCFRunLoopBeforeWaiting | kCFRunLoopExit);
  
  observer = CFRunLoopObserverCreate(NULL,
                                     activities,
                                     YES,
                                     INT_MAX,
                                     &_messageGroupRunLoopObserverCallback,
                                     NULL);
  
  if (observer) {
    CFRunLoopAddObserver(runLoop, observer, kCFRunLoopCommonModes);
    CFRelease(observer);
  }
  
  CFRunLoopSourceContext  *sourceContext = calloc(1, sizeof(CFRunLoopSourceContext));
  
  sourceContext->perform = &sourceContextCallBackLog;
  
   _runLoopSource = CFRunLoopSourceCreate(NULL, 0, sourceContext);
  
  if (_runLoopSource) {
    CFRunLoopAddSource(runLoop, _runLoopSource, kCFRunLoopCommonModes);
  }
  
}

+ (void)addCalculateTransaction:(dispatch_block_t)transaction
                       complete:(dispatch_block_t)complete {
  calculate_create_task_safely(transaction, complete);
}

@end