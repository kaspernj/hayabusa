#!/usr/bin/ruby

#This scripts start an appserver, executes a CGI-request for every FCGI-request and terminates when FCGI terminates.
#Good for programming appserver-supported projects that doesnt need threadding without running an appserver all the time.

debug = false

$stderr.puts "[hayabusa] Starting up!" if debug
error_log_file = "/tmp/hayabusa_fcgi.log"

begin
  File.unlink(error_log_file) if File.exists?(error_log_file)
rescue Errno::ENOENT
  #ignore.
end

begin
  $stderr.puts "[hayabusa] Loading libs." if debug
  require "rubygems"
  require "knjrbfw"
  require "fcgi"
  require "fileutils"
  require "#{File.dirname(Knj::Os.realpath(__FILE__))}/../lib/hayabusa.rb"
  
  fcgi = Hayabusa::Fcgi.new
  fcgi.fcgi_loop
rescue Exception => e
  if !e.is_a?(Interrupt)
    File.open(error_log_file, "w") do |fp|
      fp.puts e.inspect
      fp.puts e.backtrace
      fp.puts ""
    end
  end
  
  raise e
end