# Idempotent: adds the LovinityShare share-extension target to Runner.xcodeproj.
require 'xcodeproj'

proj_path = File.expand_path('../Runner.xcodeproj', __dir__)
proj = Xcodeproj::Project.open(proj_path)
# Idempotent: adds PrivacyInfo.xcprivacy to a target's Resources phase.
add_privacy = lambda do |group_path, target|
  next if target.resources_build_phase.files.any? { |f| f.file_ref&.path == 'PrivacyInfo.xcprivacy' }
  group = proj.main_group.find_subpath(group_path, false) || proj.main_group.new_group(group_path, group_path)
  ref = group.files.find { |f| f.path == 'PrivacyInfo.xcprivacy' } || group.new_file('PrivacyInfo.xcprivacy')
  target.add_resources([ref])
end

if (existing = proj.targets.find { |t| t.name == 'LovinityShare' })
  add_privacy.call('Runner', proj.targets.find { |t| t.name == 'Runner' })
  add_privacy.call('LovinityShare', existing)
  proj.save
  exit 0
end

runner = proj.targets.find { |t| t.name == 'Runner' }
ext = proj.new_target(:app_extension, 'LovinityShare', :ios, '15.0')

group = proj.main_group.new_group('LovinityShare', 'LovinityShare')
src = group.new_file('ShareViewController.swift')
group.new_file('Info.plist')
group.new_file('LovinityShare.entitlements')
ext.add_file_references([src])

# Supplies FLUTTER_BUILD_NAME/NUMBER for the version keys (no Pods/Flutter linking).
gen = proj.files.find { |f| f.path == 'Flutter/Generated.xcconfig' }
ext.build_configurations.each do |c|
  c.base_configuration_reference = gen
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.lovinity.lovinity.LovinityShare'
  s['INFOPLIST_FILE'] = 'LovinityShare/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'LovinityShare/LovinityShare.entitlements'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if c.name == 'Debug'
end

# Foundation links implicitly; new_target hard-codes an SDK-versioned path.
ext.frameworks_build_phase.files.dup.each(&:remove_from_project)
proj.files.select { |f| f.path.to_s.end_with?('Foundation.framework') }.each(&:remove_from_project)

runner.add_dependency(ext)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Must precede "Thin Binary" or Xcode reports a build cycle.
phases = runner.build_phases
phases.delete(embed)
phases.insert(phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }, embed)

add_privacy.call('Runner', runner)
add_privacy.call('LovinityShare', ext)
proj.save
