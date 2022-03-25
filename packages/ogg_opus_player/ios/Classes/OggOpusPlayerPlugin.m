#import "OggOpusPlayerPlugin.h"
#if __has_include(<ogg_opus_player/ogg_opus_player-Swift.h>)
#import <ogg_opus_player/ogg_opus_player-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "ogg_opus_player-Swift.h"
#endif

@implementation OggOpusPlayerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftOggOpusPlayerPlugin registerWithRegistrar:registrar];
}
@end
