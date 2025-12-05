#!/usr/bin/env ruby

require "#{File.dirname(__FILE__)}/../lib/hayabusa.rb"

knjrbfw_path = ""

ARGV.each do |arg|
  if arg == "--active_support"
    ARGV.delete(arg)
    require "active_support"
    require "active_support/core_ext"
  elsif match = arg.match(/--knjrbfw_path=(.+)/)
    knjrbfw_path = match[1]
    ARGV.delete(arg)
  else
    print "Unknown argument: '#{arg}'.\n"
    exit
  end
end

require "#{knjrbfw_path}knjrbfw"

filepath = File.dirname(__FILE__) + "/../lib/"

if File.exist?($0)
  conf_path = File.dirname($0) + "/../"
else
  conf_path = File.dirname(__FILE__) + "/../"
end

require "#{conf_path}conf/conf_vars"
require "#{$hayabusa_config["knjrbfw"]}knj/autoload"

$hayabusa = {
  :path => File.realpath(File.dirname(__FILE__))
}

Knj::Os.chdir_file(File.realpath(__FILE__))
require "#{filepath}include/class_hayabusa.rb"

print "Starting knjAppServer.\n"
require "#{conf_path}conf/conf"