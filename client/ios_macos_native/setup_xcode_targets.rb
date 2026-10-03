#!/usr/bin/env ruby
# 把两个 Packet Tunnel 扩展接进 Flutter 的 Runner 工程（iOS + macOS），幂等可重复跑。
#
#   AWGTunnel      优质节点（AmneziaWG）  bundle: <App>.AWGTunnel     链 WireGuardKitGo.xcframework
#   SingboxTunnel  免费节点（sing-box）   bundle: <App>.PacketTunnel  链 Libbox.xcframework
#
# 源码统一在 client/ios_macos_native/（iOS/macOS 共用一份），这里只建 target + 引用。
# 依赖 xcodeproj gem（随 CocoaPods 安装）。用法（在 client/ 下）：
#   ruby ios_macos_native/setup_xcode_targets.rb            # iOS + macOS
#   ruby ios_macos_native/setup_xcode_targets.rb ios        # 只 iOS
#   ruby ios_macos_native/setup_xcode_targets.rb --force    # 删掉已有扩展 target 重建
require 'xcodeproj'

CLIENT = File.expand_path('..', __dir__)
NATIVE_REL = '../ios_macos_native' # 相对 ios/ 或 macos/ 目录

EXTENSIONS = [
  {
    name: 'AWGTunnel',
    bundle_suffix: 'AWGTunnel',
    sources: ['PacketTunnelProvider.swift', '../Shared/TunnelLog.swift',
              'WireGuardKit/*.swift', 'WireGuardKitC/*.c'],
    xcframework: 'WireGuardKitGo.xcframework',
    resources: [],
    frameworks: [],
    ios_frameworks: [],
    bridging_header: 'AWGTunnel/AWGTunnel-Bridging-Header.h',
  },
  {
    name: 'SingboxTunnel',
    bundle_suffix: 'PacketTunnel',
    sources: ['PacketTunnelProvider.swift', 'SingboxPlatform.swift', '../Shared/TunnelLog.swift'],
    xcframework: 'Libbox.xcframework',
    # geoip-cn / geosite-cn 规则集随扩展打包（智能分流用，离线可用）
    resources: ['../RuleSets/geoip-cn.srs', '../RuleSets/geosite-cn.srs'],
    frameworks: ['SystemConfiguration'],
    # iOS 版 libbox 含 Chromium(naive 出站)代码，引用 UIApplication 后台任务符号。
    ios_frameworks: ['UIKit'],
    bridging_header: nil,
  },
].freeze

PLATFORMS = {
  'ios' => {
    sym: :ios, deployment: '15.0', entitlements_suffix: 'iOS',
    xcconfig: 'Flutter/TunnelExtension.xcconfig',
    xcconfig_body: <<~XC,
      // 隧道扩展 target 的基础配置（setup_xcode_targets.rb 生成）。
      // 只取 Flutter 生成的版本号（FLUTTER_BUILD_NAME/NUMBER），不带 Runner 的 Pods。
      #include? "Generated.xcconfig"
      #include "../../ios_macos_native/Signing.xcconfig"
    XC
    runner_signing_xcconfigs: ['Flutter/Debug.xcconfig', 'Flutter/Release.xcconfig'],
    runner_entitlements: 'Runner/Runner.entitlements',
  },
  'macos' => {
    sym: :osx, deployment: '13.0', entitlements_suffix: 'macOS',
    xcconfig: 'Flutter/TunnelExtension.xcconfig',
    xcconfig_body: <<~XC,
      // 隧道扩展 target 的基础配置（setup_xcode_targets.rb 生成）。
      // 只取 Flutter 生成的版本号（FLUTTER_BUILD_NAME/NUMBER），不带 Runner 的 Pods。
      #include? "ephemeral/Flutter-Generated.xcconfig"
      #include "../../ios_macos_native/Signing.xcconfig"
    XC
    runner_signing_xcconfigs: ['Runner/Configs/AppInfo.xcconfig'],
    runner_entitlements: nil, # macOS Runner 已按 Debug/Release 各自配好
  },
}.freeze

def ensure_include(path, line)
  body = File.read(path)
  return if body.include?(line)
  File.write(path, body.rstrip + "\n" + line + "\n")
  puts "  + #{File.basename(path)}: #{line}"
end

def setup(platform, force)
  cfg = PLATFORMS.fetch(platform)
  dir = File.join(CLIENT, platform)
  proj_path = File.join(dir, 'Runner.xcodeproj')
  project = Xcodeproj::Project.open(proj_path)
  runner = project.targets.find { |t| t.name == 'Runner' } or abort "no Runner target in #{proj_path}"
  app_bundle_id = runner.build_configurations.map { |c| c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] }.compact.first
  if app_bundle_id.nil? || app_bundle_id.include?('$')
    # macOS 的 bundle id 写在 AppInfo.xcconfig 里
    app_bundle_id = File.read(File.join(dir, 'Runner/Configs/AppInfo.xcconfig'))[/^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)/, 1]
  end
  puts "== #{platform}  (app bundle id: #{app_bundle_id})"

  # 扩展用的 xcconfig + 签名 Team 统一配置
  File.write(File.join(dir, cfg[:xcconfig]), cfg[:xcconfig_body])
  cfg[:runner_signing_xcconfigs].each do |rel|
    ensure_include(File.join(dir, rel), '#include "' + ('../' * (rel.count('/') + 1)) + 'ios_macos_native/Signing.xcconfig"')
  end

  # Flutter 组在 iOS/macOS 工程里 path 设定不同，统一用 SOURCE_ROOT 相对路径引用。
  flutter_group = project.main_group.find_subpath('Flutter', false) || project.main_group
  xcconfig_ref = project.files.find { |f| f.display_name == File.basename(cfg[:xcconfig]) } ||
                 flutter_group.new_reference(cfg[:xcconfig])
  xcconfig_ref.path = cfg[:xcconfig]
  xcconfig_ref.source_tree = 'SOURCE_ROOT'
  xcconfig_ref.name = File.basename(cfg[:xcconfig])

  if cfg[:runner_entitlements]
    runner.build_configurations.each do |c|
      c.build_settings['CODE_SIGN_ENTITLEMENTS'] = cfg[:runner_entitlements]
    end
  end

  # 本地化 App 名（Runner/<lang>.lproj/InfoPlist.strings）：中文「镜速加速器」，其它「MirrorSpeed VPN」。
  runner_group = project.main_group.find_subpath('Runner', false)
  unless runner_group.children.any? { |c| c.display_name == 'InfoPlist.strings' }
    variant = runner_group.new_variant_group('InfoPlist.strings')
    %w[en zh-Hans].each do |lang|
      ref = variant.new_reference("#{lang}.lproj/InfoPlist.strings")
      ref.name = lang
      ref.last_known_file_type = 'text.plist.strings'
    end
    runner.resources_build_phase.add_file_reference(variant)
    puts '  + Runner InfoPlist.strings (en / zh-Hans)'
  end
  project.root_object.known_regions = (project.root_object.known_regions + %w[en zh-Hans]).uniq

  tunnels_group = project.main_group.find_subpath('Tunnels', false) ||
                  project.main_group.new_group('Tunnels', NATIVE_REL)
  frameworks_group = project.frameworks_group

  embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
  unless embed
    embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
    embed.symbol_dst_subfolder_spec = :plug_ins
  end
  # Flutter iOS 的 "Thin Binary" 脚本在 Embed 之后会形成构建环（Cycle inside Runner），
  # 所以把扩展嵌入挪到它前面（紧跟 Embed Frameworks / Resources）。
  runner.build_phases.delete(embed)
  anchor = runner.build_phases.index { |p| p.display_name == 'Thin Binary' || p.display_name == 'Bundle Framework' } ||
           runner.build_phases.length
  runner.build_phases.insert(anchor, embed)

  EXTENSIONS.each do |ext|
    name = ext[:name]
    existing = project.targets.find { |t| t.name == name }
    if existing && force
      embed.files.select { |bf| bf.file_ref == existing.product_reference }.each(&:remove_from_project)
      runner.dependencies.select { |d| d.target == existing }.each(&:remove_from_project)
      existing.product_reference&.remove_from_project
      existing.remove_from_project
      tunnels_group.children.select { |g| g.display_name == name }.each(&:remove_from_project)
      existing = nil
    end
    if existing
      puts "  ✓ #{name} 已存在（--force 重建）"
      next
    end

    target = project.new_target(:app_extension, name, cfg[:sym], cfg[:deployment], nil, :swift)
    group = tunnels_group.new_group(name, name)

    src_dir = File.join(CLIENT, 'ios_macos_native', name)
    files = ext[:sources].flat_map { |pat| Dir.glob(File.join(src_dir, pat)).sort }
    abort "no sources for #{name}" if files.empty?
    refs = files.map do |abs|
      rel = abs.sub(src_dir + '/', '')
      sub = File.dirname(rel)
      g = sub == '.' ? group : (group.find_subpath(sub, false) || group.new_group(sub, sub))
      g.new_reference(File.basename(rel))
    end
    target.add_file_references(refs)
    %w[Info.plist].each { |f| group.new_reference(f) }
    group.new_reference("#{name}-#{cfg[:entitlements_suffix]}.entitlements")
    group.new_reference(File.basename(ext[:bridging_header])) if ext[:bridging_header]

    # 规则集等资源文件
    ext[:resources].each do |rel|
      abs = File.expand_path(File.join(src_dir, rel))
      abort "missing resource: #{abs}" unless File.exist?(abs)
      rg = group.find_subpath('Resources', true)
      rg.set_source_tree('SOURCE_ROOT')
      rg.set_path(nil)
      ref = rg.new_reference("#{NATIVE_REL}/#{rel.sub('../', '')}")
      ref.source_tree = 'SOURCE_ROOT'
      target.resources_build_phase.add_file_reference(ref)
    end

    # 静态 Go 库：只链接，不嵌入。
    xcf = frameworks_group.files.find { |f| f.path == "#{NATIVE_REL}/Frameworks/#{ext[:xcframework]}" } ||
          frameworks_group.new_reference("#{NATIVE_REL}/Frameworks/#{ext[:xcframework]}")
    xcf.source_tree = 'SOURCE_ROOT'
    target.frameworks_build_phase.add_file_reference(xcf)
    target.add_system_frameworks(['NetworkExtension'] + ext[:frameworks] + (platform == 'ios' ? ext[:ios_frameworks] : []))
    target.add_system_library_tbd('resolv')

    target.build_configurations.each do |c|
      c.base_configuration_reference = xcconfig_ref
      s = c.build_settings
      s['PRODUCT_NAME'] = '$(TARGET_NAME)'
      s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{app_bundle_id}.#{ext[:bundle_suffix]}"
      s['INFOPLIST_FILE'] = "#{NATIVE_REL}/#{name}/Info.plist"
      s['CODE_SIGN_ENTITLEMENTS'] = "#{NATIVE_REL}/#{name}/#{name}-#{cfg[:entitlements_suffix]}.entitlements"
      s['CODE_SIGN_STYLE'] = 'Automatic'
      s['SWIFT_VERSION'] = '5.0'
      s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
      s['SKIP_INSTALL'] = 'YES'
      s['ENABLE_BITCODE'] = 'NO'
      s['DEAD_CODE_STRIPPING'] = 'YES'
      s['CLANG_ENABLE_MODULES'] = 'YES'
      s['SWIFT_OBJC_BRIDGING_HEADER'] = "#{NATIVE_REL}/#{ext[:bridging_header]}" if ext[:bridging_header]
      s['HEADER_SEARCH_PATHS'] = ['$(inherited)', "$(SRCROOT)/#{NATIVE_REL}/#{name}"] if ext[:bridging_header]
      s['SWIFT_OPTIMIZATION_LEVEL'] = c.name == 'Debug' ? '-Onone' : '-O'
      if platform == 'ios'
        s['TARGETED_DEVICE_FAMILY'] = '1,2'
        s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
      else
        s['ENABLE_HARDENED_RUNTIME'] = 'YES'
        s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks', '@executable_path/../../../../Frameworks']
        s['COMBINE_HIDPI_IMAGES'] = 'YES'
      end
    end

    runner.add_dependency(target)
    bf = embed.add_file_reference(target.product_reference, true)
    bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
    puts "  + #{name} (#{target.build_configurations.first.build_settings['PRODUCT_BUNDLE_IDENTIFIER']})"
  end

  project.save
end

force = ARGV.delete('--force')
platforms = ARGV.empty? ? PLATFORMS.keys : ARGV
platforms.each { |p| setup(p, force) }
puts '完成。Team ID 填到 ios_macos_native/Signing.xcconfig（DEVELOPMENT_TEAM）。'
