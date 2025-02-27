#!/usr/bin/env ruby

#This script is used to restart the FCGI-spec-test servers.

require "rubygems"
require "php4r"

#Close down the running instance of FCGI-server-process.
fpath = "/tmp/hayabusa_fcgi_Fcgi_test_fcgi.conf"

if File.exist?t??(fpath) and fcont = File.read(fpath) and !fcont.empty?
  cont = Marshal.load(fcont)
  Process.kill("HUP", cont[:pid])
end

#Restart apache to restart any FCGI instances.
Php4r.passthru("apache2ctl restart")