#!/usr/bin/env ruby

require 'fileutils'
require 'pathname'
require 'xcodeproj'

ROOT = Pathname(__dir__).parent.expand_path
PROJECT_PATH = ROOT.join('NotchFlow.xcodeproj')
PROJECT_NAME = 'NotchFlow'
DEPLOYMENT_TARGET = '14.0'

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH.to_s)
project.root_object.attributes['LastUpgradeCheck'] = '2650'
project.root_object.attributes['TargetAttributes'] = {}

target = project.new_target(:application, PROJECT_NAME, :osx, DEPLOYMENT_TARGET)
target.product_name = PROJECT_NAME

info_plist_ref = project.main_group.new_file('App/Info.plist')

sources_group = project.main_group.find_subpath('Sources', true)
source_refs = Dir.glob(ROOT.join('Sources/NotchFlow/**/*.swift')).sort.map do |path|
  relative = Pathname(path).relative_path_from(ROOT).to_s
  sources_group.new_file(relative)
end
target.add_file_references(source_refs)

docs_group = project.main_group.find_subpath('Docs', true)
[
  'README.md',
  'research/competitors.md',
  'research/feature-list.md',
  'research/v1-scope.md',
].each do |path|
  docs_group.new_file(path)
end

framework_paths = [
  '/System/Library/Frameworks/AppKit.framework',
  '/System/Library/Frameworks/Carbon.framework',
  '/System/Library/Frameworks/IOKit.framework',
  '/System/Library/Frameworks/ServiceManagement.framework',
  '/System/Library/Frameworks/SwiftUI.framework',
]

framework_refs = framework_paths.map do |path|
  project.frameworks_group.new_file(path)
end
framework_refs.each do |ref|
  target.frameworks_build_phase.add_file_reference(ref, true)
end

target.build_configurations.each do |config|
  settings = config.build_settings
  settings['INFOPLIST_FILE'] = info_plist_ref.path
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.notchflow.app'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SWIFT_VERSION'] = '6.0'
  settings['MACOSX_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['CLANG_ENABLE_MODULES'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = ''
  settings['ENABLE_APP_SANDBOX'] = 'NO'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/../Frameworks'
  settings['MARKETING_VERSION'] = '0.1.0'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'NO'
end

project.recreate_user_schemes
project.save
