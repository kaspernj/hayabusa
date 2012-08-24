#!/usr/bin/ruby

#This scripts start an appserver, executes a CGI-request for every FCGI-request and terminates when FCGI terminates.
#Good for programming appserver-supported projects that doesnt need threadding without running an appserver all the time.

error_log_file = "/tmp/hayabusa_fcgi.log"

begin
  File.unlink(error_log_file) if File.exists?(error_log_file)
rescue Errno::ENOENT
  #ignore.
end

begin
  require "rubygems"
  require "fcgi"
  require "fileutils"
  
  #Try to load development-version to enable debugging without doing constant gem-installations.
  path = "/home/kaspernj/Ruby/knjrbfw/lib/knjrbfw.rb"
  if File.exists?(path)
    require path
  else
    require "knjrbfw"
  end
  
  #Load 'Hayabusa' and start the FCGI-loop to begin handeling requests.
  require "#{File.dirname(Knj::Os.realpath(__FILE__))}/../lib/hayabusa.rb"
  fcgi = Hayabusa::Fcgi.new
  fcgi.fcgi_loop
rescue Exception => e
  if !e.is_a?(Interrupt)
    #Log error to the log-file if something happened.
    File.open(error_log_file, "w") do |fp|
      fp.puts e.inspect
      fp.puts e.backtrace
      fp.puts ""
    end
  end
  
  #Just raise it normally as if a normal error occurred.
  raise e
end