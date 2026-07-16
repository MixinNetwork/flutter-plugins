#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint desktop_drop.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'desktop_drop'
  s.version          = '0.5.0'
  s.summary          = 'A plugin which allows user dragging files to your flutter desktop applications.'
  s.description      = <<-DESC
A plugin which allows user dragging files to your flutter desktop applications.
Supports files, folders, text, and URLs from Finder, Dock, and Chromium-based apps.
                       DESC
  s.homepage         = 'https://github.com/omar-hanafy/desktop_drop'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'MixinNetwork' => 'https://github.com/omar-hanafy' }
  s.source           = { :path => '.' }
  s.source_files     = 'desktop_drop/Sources/desktop_drop/**/*.{h,m,swift}'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '11.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
