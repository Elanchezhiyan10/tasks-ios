require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

runner_target = project.targets.find { |t| t.name == 'Runner' }
widget_target = project.targets.find { |t| t.name == 'TaskWidgetExtension' }

if widget_target.nil?
  puts "Creating TaskWidgetExtension target..."
  widget_target = project.new_target(
    :app_extension,
    'TaskWidgetExtension',
    :ios,
    '15.0',
    project.products_group,
    :swift
  )
end

# Explicit product naming to prevent nameless .appex output
widget_target.product_name = 'TaskWidgetExtension'
if widget_target.product_reference
  widget_target.product_reference.name = 'TaskWidgetExtension.appex'
  widget_target.product_reference.path = 'TaskWidgetExtension.appex'
end

# Main group for extension source files
group = project.main_group.find_subpath('TaskWidgetExtension', true)
group.set_source_tree('<group>')
group.set_path('TaskWidgetExtension')
group.clear

swift_file = group.new_file('TaskWidget.swift')
plist_file = group.new_file('Info.plist')

# Source compilation
widget_target.source_build_phase.clear
widget_target.source_build_phase.add_file_reference(swift_file)

# Build settings
widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'TaskWidgetExtension'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.example.flutterPgi.TaskWidgetExtension'
  config.build_settings['INFOPLIST_FILE'] = 'TaskWidgetExtension/Info.plist'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
  config.build_settings['CODE_SIGN_IDENTITY'] = ''
  config.build_settings['GENERATE_INFOPLIST_KEY_CFBundleDisplayName'] = 'Task Focus'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks'
  ]
end

# Dependency on Runner
unless runner_target.dependencies.any? { |d| d.target == widget_target }
  runner_target.add_dependency(widget_target)
end

# Embed in Runner PlugIns
embed_phase = runner_target.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
if embed_phase.nil?
  embed_phase = runner_target.new_copy_files_build_phase('Embed Foundation Extensions')
  embed_phase.dst_subfolder_spec = '13' # PlugIns
  embed_phase.dst_path = ''
end

embed_phase.clear
build_file = embed_phase.add_file_reference(widget_target.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Reorder build phases: Embed Foundation Extensions MUST be placed BEFORE Thin Binary
thin_index = runner_target.build_phases.find_index { |p| (p.respond_to?(:name) && p.name == 'Thin Binary') || (p.respond_to?(:display_name) && p.display_name == 'Thin Binary') }
if thin_index
  runner_target.build_phases.delete(embed_phase)
  runner_target.build_phases.insert(thin_index, embed_phase)
  puts "Reordered build phases: placed Embed Foundation Extensions before Thin Binary at index #{thin_index}"
end

project.save
puts "Successfully configured TaskWidgetExtension with product name TaskWidgetExtension.appex!"
