#!/usr/bin/env ruby

# This script checks if the hayabusa is running - if not it forks and start it.
require "rubygems"
require "optparse"
Dir.chdir("#{File.dirname(__FILE__)}/../")

begin
  options = {
    :command => "ruby hayabusa_start.rb",
    :title => "hayabusa",
    :forking => true
  }
  OptionParser.new do |opts|
    opts.banner = "Usage: hayabusa.rb [options]"
    
    opts.on("--command=[cmd]", "Run verbosely.") do |cmd|
      options[:command] = cmd
    end
    
    opts.on("--title=[title]", "The title of the appserver that should be checked for.") do |title|
      options[:title] = title
    end
    
    opts.on("--forking=[forkval]", "If you want the script to fork or not.") do |forking|
      if forking.to_i >= 1
        options[:forking] = true
      else
        options[:forking] = false
      end
    end
    
    opts.on("--knjrbfw_path=[path]") do |path|
      options[:knjrbfw_path] = path
    end
  end.parse!
rescue OptionParser::InvalidOption => e
  print "#{e.message}\n"
  exit
end

if !options[:title]
  print "No title was given.\n"
  exit
end

if !options[:command]
  print "No command to execute was given.\n"
  exit
end

require "#{options[:knjrbfw_path]}knjrbfw"

tmpdir = "#{Knj::Os.tmpdir}/hayabusa"
tmppath = "#{tmpdir}/run_#{options[:title]}"
count = 0

if File.exists?(tmppath)
  pid = File.read(tmppath).to_s.strip
  count = Knj::Unix_proc.list("pids" => [pid]).length if pid.to_s.length > 0
end

exit if count > 0

if options[:forking]
  exec(options[:command]) if fork.nil?
else
  exec(options[:command])
end