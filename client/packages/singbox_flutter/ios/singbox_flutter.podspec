Pod::Spec.new do |s|
  s.name             = 'singbox_flutter'
  s.version          = '0.0.1'
  s.summary          = 'sing-box engine for MirrorSpeed (shared / free nodes) — iOS.'
  s.description      = <<-DESC
Thin Flutter plugin that drives a NEPacketTunnelProvider network extension
running libbox (sing-box). The app talks to it over the same channels as
Android: MethodChannel `mirrorspeed/singbox` + EventChannel
`mirrorspeed/singbox/stage`.
                       DESC
  s.homepage         = 'https://www.mirrorspeed.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'MirrorSpeed' => 'support@mirrorspeed.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  # NetworkExtension 用于管理隧道配置（NETunnelProviderManager）。
  s.frameworks = 'NetworkExtension'
end
