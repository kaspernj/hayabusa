#!/usr/bin/ruby

#This scripts start an appserver, executes a HTTP-request for every FCGI-request and terminates when FCGI terminates.
#Good for programming appserver-supported projects that doesnt need threadding without running an appserver all the time.

#It doesnt support shared threadding or objects because multiple instances in form of processes will be executed.

#Its a bit slower because it needs to flush writes to the database at end of every request and re-read them on spawn, because multiple instances might be present.

error_log_file = "/tmp/hayabusa_fcgi.log"
File.unlink(error_log_file) if File.exists?(error_log_file)

begin
  require "rubygems"
  require "knjrbfw"
  require "fcgi"
  require "#{File.dirname(Knj::Os.realpath(__FILE__))}/../lib/hayabusa.rb"
  
  #Spawn CGI-variable to emulate FCGI part.
  cgi_tools = Hayabusa::Cgi_tools.new
  
  #We cant define the Hayabusa-server untuil we receive the first headers, so wait for the first request.
  hayabusa = nil
  
  FCGI.each_cgi do |cgi|
    begin
      cgi_tools.cgi = cgi
      
      if !hayabusa
        raise "No HTTP_HAYABUSA_FCGI_CONFIG-header was given." if !cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]
        require cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]
        
        begin
          conf = Hayabusa::FCGI_CONF
        rescue NameError
          raise "No 'Hayabusa::FCGI_CONF'-constant was spawned by '#{cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]}'."
        end
        
        hayabusa_conf = Hayabusa::FCGI_CONF[:hayabusa]
        hayabusa_conf.merge!(
          :cmdline => false,
          :mode => :cgi
        )
        hayabusa_conf[:doc_root] = "" if !hayabusa_conf.key?(:doc_root)
        hayabusa = Hayabusa.new(hayabusa_conf)
      end
      
      
      #Enforce $stdout variable.
      $stdout = hayabusa.cio
      
      
      #The rest is copied from the FCGI-part.
      headers = {}
      cgi.env_table.each do |key, val|
        if key[0, 5] == "HTTP_" and key != "HTTP_HAYABUSA_FCGI_CONFIG"
          key = key[5, key.length].gsub("_", " ").gsub(" ", "-")
          headers[key] = val
        end
      end
      
      meta = cgi.env_table.to_hash
      
      uri = Knj::Web.parse_uri(meta["REQUEST_URI"])
      meta["PATH_TRANSLATED"] = File.basename(uri[:path])
      
      cgi_data = {
        :cgi => cgi,
        :headers => headers,
        :get => Knj::Web.parse_urlquery(cgi.env_table["QUERY_STRING"], :urldecode => true, :force_utf8 => true),
        :meta => meta
      }
      if cgi.request_method == "POST"
        cgi_data[:post] = cgi_tools.convert_fcgi_post(cgi.params)
      else
        cgi_data[:post] = {}
      end
      
      hayabusa.config[:cgi] = cgi_data
      
      
      #Handle request.
      hayabusa.start
    rescue Exception => e
      cgi.print "Content-Type: text/html\r\n"
      cgi.print "\r\n"
      cgi.print Knj::Errors.error_str(e, :html => true)
      cgi.print Knj.p(cgi_data, true) if cgi_data
    end
  end
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