require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

runner_target = project.targets.find { |t| t.name == 'Runner' }
widget_target = project.targets.find { |t| t.name == 'TaskWidgetExtension' }

if widget_target.nil?
  puts "Creating TaskWidgetExtension target..."
  widget_target = project.new_target(:app_extension, 'TaskWidgetExtension', :ios, '15.0')
  
  group = project.main_group.find_subpath('TaskWidgetExtension', true)
  group.set_source_tree('<group>')
  group.set_path('TaskWidgetExtension')

  swift_file = group.new_file('TaskWidget.swift')
  plist_file = group.new_file('Info.plist')

  widget_target.source_build_phase.add_file_reference(swift_file)

  widget_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.example.flutterPgi.TaskWidgetExtension'
    config.build_settings['INFOPLIST_FILE'] = 'TaskWidgetExtension/Info.plist'
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
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

  runner_target.add_dependency(widget_target)
  
  embed_phase = runner_target.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
  if embed_phase.nil?
    embed_phase = runner_target.new_copy_files_build_phase('Embed Foundation Extensions')
    embed_phase.dst_subfolder_spec = '13' # PlugIns
  end
  embed_phase.add_file_reference(widget_target.product_reference, true)

  project.save
  puts "TaskWidgetExtension successfully configured in Xcode project!"
else
  puts "TaskWidgetExtension target already exists."
end
