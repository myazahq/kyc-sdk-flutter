Pod::Spec.new do |s|
  s.name             = 'kyc_sdk_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Myaza KYC SDK — native face detection (Apple Vision on iOS).'
  s.description      = <<-DESC
iOS face detection for the Myaza KYC Flutter SDK via Apple's Vision framework.
Vision ships arm64 simulator slices and pulls no GoogleMLKit pod, so the SDK
builds and runs on Apple-Silicon iOS simulators.
                       DESC
  s.homepage         = 'https://github.com/myazahq/kyc-sdk-flutter'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Myaza' => 'dev@myazahq.co' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain an i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
