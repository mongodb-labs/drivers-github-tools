# frozen_string_literal: true

# This script generates the name of a gem file based on the provided
# gem name and version. It takes into account whether it is running
# under JRuby to append "-java" to the gem name if necessary.
#
# Usage:
# ruby gem_name.rb <gem_name> <gem_version>

if ARGV.length != 2
  puts "Usage: ruby gem_name.rb <gem_name> <gem_version>"
  exit 1
end

gem_name = ARGV.first
gem_version = ARGV.last

base_name = "#{gem_name}-#{gem_version}"
base_name = "#{base_name}-java" if defined?(JRUBY_VERSION)

puts "#{base_name}.gem"
