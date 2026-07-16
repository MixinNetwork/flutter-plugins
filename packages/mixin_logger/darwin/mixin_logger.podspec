#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint mixin_logger.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'mixin_logger'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # The SPM source contains a forwarder that includes the shared implementation
  # from `src/` so CocoaPods and Swift Package Manager compile the same code.
  s.source           = { :path => '.' }
  s.source_files     = 'mixin_logger/Sources/mixin_logger/**/*'
  s.public_header_files = 'mixin_logger/Sources/mixin_logger/include/**/*.h'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '11.0'
  s.osx.deployment_target = '10.11'

  # Flutter.framework does not contain an i386 slice.
  s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
