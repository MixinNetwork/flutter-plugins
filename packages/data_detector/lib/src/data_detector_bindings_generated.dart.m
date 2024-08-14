#include <stdint.h>

#import <Foundation/NSRegularExpression.h>
typedef void  (^ListenerBlock)(NSTextCheckingResult* , NSMatchingFlags , BOOL * );
ListenerBlock wrapListenerBlock_ObjCBlock_ffiVoid_NSTextCheckingResult_NSMatchingFlags_bool(ListenerBlock block) {
  ListenerBlock wrapper = [^void(NSTextCheckingResult* arg0, NSMatchingFlags arg1, BOOL * arg2) {
    block([arg0 retain], arg1, arg2);
  } copy];
  [block release];
  return wrapper;
}
