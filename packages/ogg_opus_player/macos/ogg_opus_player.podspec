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
  s.source_files     = 'Classes/**/*', 'Headers/**/*'
  s.dependency 'FlutterMacOS'
  s.osx.vendored_libraries = 'Libs/libogg.a', 'Libs/libopus.a', 'Libs/libopusenc.a', 'Libs/libopusfile.a'

  s.platform = :osx, '10.12'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
