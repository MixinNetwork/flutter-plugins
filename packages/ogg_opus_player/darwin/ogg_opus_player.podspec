#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ogg_opus_player.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ogg_opus_player'
  s.version          = '0.0.1'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'ogg_opus_player/Sources/**/*'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.frameworks = 'Speech', 'AVFoundation', 'AudioToolbox'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.ios.vendored_frameworks = 'ogg_opus_player/Frameworks/libogg.xcframework', 'ogg_opus_player/Frameworks/libopus.xcframework', 'ogg_opus_player/Frameworks/libopusenc.xcframework', 'ogg_opus_player/Frameworks/libopusfile.xcframework'
  s.osx.vendored_libraries = 'ogg_opus_player/Frameworks/libogg.xcframework/macos-arm64_x86_64/libogg.a', 'ogg_opus_player/Frameworks/libopus.xcframework/macos-arm64_x86_64/libopus.a', 'ogg_opus_player/Frameworks/libopusenc.xcframework/macos-arm64_x86_64/libopusenc.a', 'ogg_opus_player/Frameworks/libopusfile.xcframework/macos-arm64_x86_64/libopusfile.a'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386', 'ENABLE_BITCODE' => 'NO' }
  s.swift_version = '5.0'
end
