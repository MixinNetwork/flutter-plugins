Pod::Spec.new do |s|
  s.name             = 'desktop_drop'
  s.version          = '0.0.1'
  s.summary          = 'Drag-and-drop support for Flutter (now with iOS support).'
  s.description      = <<-DESC
  Cross-platform drag-and-drop plugin for Flutter, extended to support iOS via UIDropInteraction.
  DESC
  s.homepage         = 'https://github.com/your-org/desktop_drop'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your.email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'desktop_drop/Sources/desktop_drop/**/*.swift'
  s.dependency 'Flutter'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.platform     = :ios, '11.0'
  s.swift_version = '5.0'
  s.resource_bundles = {'desktop_drop_privacy' => ['desktop_drop/Sources/desktop_drop/PrivacyInfo.xcprivacy']}

end
