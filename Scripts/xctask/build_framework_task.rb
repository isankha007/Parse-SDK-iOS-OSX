#!/usr/bin/env ruby
#
# Copyright (c) 2015-present, Parse, LLC.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree. An additional grant
# of patent rights can be found in the PATENTS file in the same directory.
#

require 'naturally'
require_relative 'build_task'

module XCTask
  # This class defines all possible framework types for BuildFrameworkTask.
  class FrameworkType
    IOS = 'ios'
    OSX = 'osx'

    def self.verify(type)
      if type.nil? || (type != IOS && type != OSX)
        fail "Unknown framework type. Available types: 'ios', 'osx'."
      end
    end
  end

  # This class adds ability to easily configure a building of iOS/OSX framework and execute the build process.
  class BuildFrameworkTask
    attr_accessor :directory
    attr_accessor :build_directory
    attr_accessor :framework_type
    attr_accessor :framework_name

    attr_accessor :workspace
    attr_accessor :project
    attr_accessor :scheme
    attr_accessor :configuration

    def initialize
      @directory = '.'
      @build_directory = './build'
      yield self if block_given?
    end

    def execute
      verify
      prepare_build
      build
    end

    private

    def verify
      FrameworkType.verify(@framework_type)
    end

    def prepare_build
      Dir.chdir(@directory) unless @directory.nil?
    end

    def build
      case @framework_type
      when FrameworkType::IOS
        build_ios_framework
      when FrameworkType::OSX
        build_osx_framework
      end
    end

    def build_ios_framework
      framework_paths = []
      framework_paths << build_framework('iphoneos')
      framework_paths << build_framework('iphonesimulator')
      final_path = final_framework_path

      system("rm -rf #{final_path} && cp -R #{framework_paths[0]} #{final_path}")

      binary_name = File.basename(@framework_name, '.framework')
      system("rm -rf #{final_path}/#{binary_name}")

      lipo_command = 'lipo -create'
      framework_paths.each do |path|
        lipo_command += " #{path}/#{binary_name}"
      end
      lipo_command += " -o #{final_path}/#{binary_name}"

      result = system(lipo_command)
      unless result
        puts 'Failed to lipo iOS framework.'
        exit(1)
      end
      result
    end

    def build_osx_framework
      build_path = build_framework('macosx')
      final_path = final_framework_path
      system("rm -rf #{final_path} && cp -R #{build_path} #{final_path}")
    end

    def build_framework(sdk)
      configuration_directory = configuration_build_directory(sdk)
      build_task = BuildTask.new do |t|
        t.directory = @directory
        t.project = @project
        t.workspace = @workspace

        t.scheme = @scheme
        t.sdk = latest_sdk(sdk)
        t.configuration = @configuration

        t.actions = [BuildAction::CLEAN, BuildAction::BUILD]
        t.formatter = BuildFormatter::XCPRETTY

        t.additional_options = { 'CONFIGURATION_BUILD_DIR' => "'#{configuration_directory}'" }
      end

      result = build_task.execute
      unless result
        puts "Failed to build framework for #{sdk}."
        exit(1)
      end

      "#{configuration_directory}/#{@framework_name}"
    end

    def latest_sdk(platform)
      sdks = Naturally.sort(`xcodebuild -showsdks`.scan(/-sdk (.*)$/)).reverse.flatten
      sdks.select { |s| s =~ /#{platform}/ }[0]
    end

    def configuration_build_directory(sdk)
      "#{@build_directory}/#{@configuration}-#{@framework_type}-#{sdk}"
    end

    def final_framework_path
      "#{@build_directory}/#{@framework_name}"
    end
  end
end
