#import "PasteboardPlugin.h"
#if __has_include(<pasteboard/pasteboard-Swift.h>)
#import <pasteboard/pasteboard-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "pasteboard-Swift.h"
#endif

@implementation PasteboardPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftPasteboardPlugin registerWithRegistrar:registrar];
}
@end
