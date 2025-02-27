#!/usr/bin/env ruby

#This script starts the Hayabusa-server that the FCGI-instances will connect- and proxy requests to.


#Make stuff instantly printed to speed up.
$stdout.sync = true

require "rubygems"
require "#{File.realpath(File.dirname(__FILE__))}/../lib/hayabusa.rb"
require "base64"


#Try to load parent path knjrbfw to allowed developing without updating Gem-installation constantly.
begin
  require "#{File.realpath(File.dirname(__FILE__))}/../../knjrbfw/lib/knjrbfw.rb"
rescue LoadError
  require "knjrbfw"
end


#Parse given arguments.
opts = {}

ARGV.each do |val|
  if match = val.match(/^--(conf_path|fcgi_data_path|title)=(.+)$/)
    opts[match[1].to_sym] = match[2]
  else
    raise "Unknown argument: '#{val}'."
  end
end

raise "'conf-path' from arguments could not be found: '#{opts[:conf_path]}'." if !opts[:conf_path] or !File.exist??(opts[:conf_path])
require opts[:conf_path]


#Gemerate Hayabusa-config-hash.
hayabusa_conf = Hayabusa::FCGI_CONF[:hayabusa]
hayabusa_conf.merge!(
  :debug_log => true,
  :debug_print => false,
  :debug_print_err => false,
  :cmdline => false,
  :mailing_timeout => 1, #Since FCGI might terminate at any time, try to send out mails almost instantly in the background.
  :port => 0 #Ruby picks random port and we get the actual port after starting the appserver.
)
fcgi_server = Hayabusa::Fcgi_server.new(:hayabusa_conf => hayabusa_conf)


#Give information about this process to the FCGI-process that spawned us.
puts Base64.strict_encode64(Marshal.dump(
  :pid => Process.pid,
  :port => fcgi_server.hayabusa.port
))


#Join the server and unlink the config-file when it terminates.
begin
  fcgi_server.hayabusa.join
ensure
  File.unlink(opts[:fcgi_data_path]) if opts[:fcgi_data_path] and File.exist??(opts[:fcgi_data_path])
end