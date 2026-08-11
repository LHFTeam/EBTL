#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds `ios/Runner/GoogleService-Info.plist` to the Runner target's bundle
# resources.
#
# The plist is gitignored (like `android/app/google-services.json`), so it can
# never be a permanent file reference in the Xcode project: a missing build
# input aborts the build for everyone who does not have it. CI decodes the
# plist from a secret and then runs this script to wire it into the target for
# that build only. Without it, the file sits in the source tree but never
# reaches the .app bundle, and `Firebase.initializeApp()` fails at runtime —
# silently, because `FirebaseBootstrap` swallows the error and leaves push,
# Crashlytics, and Analytics disabled.
#
# Locally, do the same thing once by dragging the plist into the Runner group
# in Xcode with "Copy items if needed" unchecked and the Runner target ticked.
#
# Usage: ruby ios/scripts/add_google_service_info.rb

require 'xcodeproj'

PLIST_NAME = 'GoogleService-Info.plist'

ios_dir = File.expand_path('..', __dir__)
project_path = File.join(ios_dir, 'Runner.xcodeproj')
plist_path = File.join(ios_dir, 'Runner', PLIST_NAME)

abort("#{plist_path} does not exist — decode it before running this script.") unless File.exist?(plist_path)

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' }
abort('No "Runner" target in Runner.xcodeproj.') if target.nil?

already_bundled = target.resources_build_phase.files.any? do |build_file|
  build_file.file_ref&.path&.end_with?(PLIST_NAME)
end

if already_bundled
  puts "#{PLIST_NAME} is already in the Runner target's resources — nothing to do."
  exit 0
end

group = project.main_group.find_subpath('Runner', true)
file_ref = group.files.find { |f| f.path&.end_with?(PLIST_NAME) } || group.new_reference(plist_path)
target.resources_build_phase.add_file_reference(file_ref, true)
project.save

puts "Added #{PLIST_NAME} to the Runner target's bundle resources."
