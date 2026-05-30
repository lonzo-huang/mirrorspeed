Pod::Spec.new do |s|
  s.name             = 'amneziawg_flutter'
  s.version          = '0.1.0'
  s.summary          = 'AmneziaWG Flutter plugin (iOS/macOS)'
  s.homepage         = 'https://github.com/amnezia-vpn/amneziawg-flutter'
  s.license          = { :type => 'MIT' }
  s.author           = { 'MirrorSpeed' => 'dev@mirrorspeed.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.ios.deployment_target  = '15.0'

  s.dependency 'Flutter'

  # AmneziaWireGuardKit — AWG-capable replacement for WireGuardKit.
  # Add to your Podfile:
  #   pod 'AmneziaWireGuardKit', :git => 'https://github.com/amnezia-vpn/AmneziaWireGuardKit.git'
  s.dependency 'AmneziaWireGuardKit'
end
