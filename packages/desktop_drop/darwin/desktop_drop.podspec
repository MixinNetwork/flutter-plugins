#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint desktop_drop.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'desktop_drop'
  s.version          = '0.0.1'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  # Darwin forwarders include the shared C/C++ implementation from ../src.
  s.source_files     = 'desktop_drop/Sources/**/*.{h,m,c,cc,swift}'
  s.resource_bundles = {
    'desktop_drop_privacy' => ['desktop_drop/Sources/desktop_drop/PrivacyInfo.xcprivacy']
  }
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.13'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17'
  }
  s.libraries = 'c++'
  s.swift_version = '5.0'
end
