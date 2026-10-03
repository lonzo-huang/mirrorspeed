Pod::Spec.new do |s|
  s.name             = 'amneziawg_flutter'
  s.version          = '0.1.0'
  s.summary          = 'AmneziaWG Flutter plugin — iOS / macOS (app side).'
  s.description      = <<-DESC
App-side plugin: drives the AWGTunnel NEPacketTunnelProvider extension through
NETunnelProviderManager. The extension itself (amneziawg-go + WireGuardKit) lives in
client/ios_macos_native/AWGTunnel and is wired into Runner by setup_xcode_targets.rb.
                       DESC
  s.homepage         = 'https://www.mirrorspeed.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'MirrorSpeed' => 'support@mirrorspeed.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  s.frameworks = 'NetworkExtension'
end
