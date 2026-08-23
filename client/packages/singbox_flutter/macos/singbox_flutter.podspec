Pod::Spec.new do |s|
  s.name             = 'singbox_flutter'
  s.version          = '0.0.1'
  s.summary          = 'sing-box engine for MirrorSpeed (shared / free nodes) — macOS.'
  s.description      = 'macOS build of the singbox_flutter plugin (shares Swift source with iOS).'
  s.homepage         = 'https://www.mirrorspeed.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'MirrorSpeed' => 'support@mirrorspeed.com' }
  s.source           = { :path => '.' }
  # 与 iOS 共用同一份 Swift（SingboxFlutterPlugin.swift 内已用 #if os() 分平台）。
  s.source_files     = '../ios/Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  s.frameworks = 'NetworkExtension'
end
