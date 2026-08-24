#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_startup_metrics.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_startup_metrics'
  s.version          = '0.0.1'
  s.summary          = 'Flutter cold-start measurement, process start to first rasterized frame.'
  s.description      = <<-DESC
Measures Flutter cold start from OS process start to the first frame Flutter
actually rasterizes, with a phase breakdown. Reports the numbers; sends them nowhere.
                       DESC
  s.homepage         = 'https://github.com/brunovsiqueira/flutter_startup_metrics'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Bruno Siqueira' => 'brunofcslbe@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_startup_metrics_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
