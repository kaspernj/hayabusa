#!/usr/bin/ruby

#This scripts start an appserver, executes a HTTP-request and terminates.
#Good for programming appserver-supported projects without running an appserver all the time,
#but really slow because of startup for every request.

begin
  #Read real path.
  file = __FILE__
  file = File.readlink(file) if File.symlink?(file)
  file = File.realpath(file)
  
  require "#{File.dirname(file)}/../lib/hayabusa.rb"
  require "knjrbfw"
  
  #Spawn CGI-variable to emulate FCGI part.
  cgi_tools = Hayabusa::Cgi_tools.new
  
  require "cgi"
  cgi = CGI.new
  cgi_tools.cgi = cgi
  
  #print "Content-Type: text/html\r\n"
  #print "\r\n"
  
  raise "No HTTP_HAYABUSA_CGI_CONFIG-header was given." if !ENV["HTTP_HAYABUSA_CGI_CONFIG"]
  require ENV["HTTP_HAYABUSA_CGI_CONFIG"]
  
  begin
    conf = Hayabusa::CGI_CONF
  rescue NameError
    raise "No 'Hayabusa::CGI_CONF'-constant was spawned by '#{ENV["HTTP_HAYABUSA_CGI_CONFIG"]}'."
  end
  
  #The rest is copied from the FCGI-part.
  headers = {}
  cgi_tools.env_table.each do |key, val|
    if key[0, 5] == "HTTP_" and key != "HTTP_HAYABUSA_CGI_CONFIG"
      key = key[5, key.length].gsub("_", " ").gsub(" ", "-")
      headers[key] = val
    end
  end
  
  cgi_data = {
    :headers => headers,
    :get => Knj::Web.parse_urlquery(cgi_tools.env_table["QUERY_STRING"], :urldecode => true, :force_utf8 => true),
    :meta => cgi_tools.env_table.to_hash
  }
  if cgi_tools.request_method == "POST"
    cgi_data[:post] = cgi_tools.convert_fcgi_post(cgi_tools.params)
  else
    cgi_data[:post] = {}
  end
  
  #Spawn appserver.
  hayabusa_conf = {
    :cmdline => false,
    :events => false,
    :cleaner => false,
    :dbrev => false,
    :mail_require => false,
    :debug => false,
    :cgi => cgi_data,
    :webserver => false
  }
  hayabusa_conf.merge!(Hayabusa::CGI_CONF[:hayabusa]) if Hayabusa::CGI_CONF[:hayabusa]
  hayabusa = Hayabusa.new(hayabusa_conf).start_cgi_request
rescue Exception => e
  print "Content-Type: text/html\r\n"
  print "\n\n"
  
  if Kernel.const_defined?(:Knj)
    print Knj::Errors.error_str(e, {:html => true})
  else
    puts e.inspect
    puts e.backtrace
  end
  
  begin
    hayabusa.stop if hayabusa
  rescue => e
    print "<br />\n<br />\n#{Knj::Errors.error_str(e, {:html => true})}"
  end
end