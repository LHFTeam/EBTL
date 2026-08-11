#!/usr/bin/env ruby
# frozen_string_literal: true

# Applies manual signing settings to the Runner target's Release configuration.
#
# These cannot be passed to `xcodebuild` on the command line. Command-line build
# settings apply to *every* target in the build, and this project links its
# plugins through Swift Package Manager, so a globally specified
# PROVISIONING_PROFILE_SPECIFIER makes each package target fail with
# "<target> does not support provisioning profiles, but provisioning profile
# <name> has been manually specified" — around 25 of them, from Firebase,
# Stripe, GoogleUtilities, Facebook, and the Flutter plugins.
#
# Writing them onto the Runner target instead scopes them to the one target that
# actually signs. Target-level settings also override the project-level
# CODE_SIGN_IDENTITY[sdk=iphoneos*] left over from the Flutter template.
#
# The edit is made to the CI checkout only and is never committed, so a
# developer's Mac keeps building with automatic signing.
#
# Usage: APPLE_TEAM_ID=… CODE_SIGN_IDENTITY=… PROVISIONING_PROFILE_NAME=… \
#          ruby ios/scripts/set_signing.rb

require 'xcodeproj'

team = ENV.fetch('APPLE_TEAM_ID')
identity = ENV.fetch('CODE_SIGN_IDENTITY')
profile = ENV.fetch('PROVISIONING_PROFILE_NAME')

project_path = File.join(File.expand_path('..', __dir__), 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' }
abort('No "Runner" target in Runner.xcodeproj.') if target.nil?

configuration = target.build_configurations.find { |c| c.name == 'Release' }
abort('No Release configuration on the Runner target.') if configuration.nil?

settings = configuration.build_settings
settings['CODE_SIGN_STYLE'] = 'Manual'
settings['DEVELOPMENT_TEAM'] = team
settings['CODE_SIGN_IDENTITY'] = identity
settings['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = identity
settings['PROVISIONING_PROFILE_SPECIFIER'] = profile
project.save

puts "Runner/Release will sign as '#{identity}' with profile '#{profile}' (team #{team})."
