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
  s.source_files = 'Classes/**/*', 'Headers/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  s.ios.vendored_frameworks= 'Frameworks/libogg.xcframework', 'Frameworks/libopus.xcframework', 'Frameworks/libopusenc.xcframework', 'Frameworks/libopusfile.xcframework'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386', 'ENABLE_BITCODE' => 'NO' }
  s.swift_version = '5.0'
end
