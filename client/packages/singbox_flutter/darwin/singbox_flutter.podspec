Pod::Spec.new do |s|
  s.name             = 'singbox_flutter'
  s.version          = '0.0.1'
  s.summary          = 'sing-box engine for MirrorSpeed (shared / free nodes) — iOS / macOS.'
  s.description      = <<-DESC
Thin Flutter plugin that drives the SingboxTunnel NEPacketTunnelProvider extension
(libbox / sing-box, source in client/ios_macos_native/SingboxTunnel). Same channels as
Android: MethodChannel `mirrorspeed/singbox` + EventChannel `mirrorspeed/singbox/stage`.
                       DESC
  s.homepage         = 'https://www.mirrorspeed.com'
  s.license          = { :type => 'Proprietary' }
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
