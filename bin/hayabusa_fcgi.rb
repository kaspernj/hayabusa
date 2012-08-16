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
  
  #Spawn CGI-variable to emulate FCGI part.
  cgi_tools = Hayabusa::Cgi_tools.new
  
  #We cant define the Hayabusa-server untuil we receive the first headers, so wait for the first request.
  hayabusa = nil
  fcgi_proxy = nil
  
  $stderr.puts "[hayabusa] Starting FCGI." if debug
  FCGI.each_cgi do |cgi|
    begin
      #cgi.print "Content-Type: text/html\r\n"
      #cgi.print "\r\n"
      
      cgi_tools.cgi = cgi
      
      if !hayabusa
        raise "No HTTP_HAYABUSA_FCGI_CONFIG-header was given." if !cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]
        require cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]
        raise "No 'Hayabusa::FCGI_CONF'-constant was spawned by '#{cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]}'." if !Hayabusa.const_defined?(:FCGI_CONF)
        conf = Hayabusa::FCGI_CONF
        
        hayabusa_conf = Hayabusa::FCGI_CONF[:hayabusa]
        hayabusa_conf.merge!(
          :cmdline => false,
          :port => 0 #Ruby picks random port and we get the actual port after starting the appserver.
        )
        
        #Figure out if this should be a host-FCGI-process or a proxy-FCGI-process.
        fcgi_config_fp = "#{Knj::Os.tmpdir}/hayabusa_fcgi_#{hayabusa_conf[:title]}_fcgi.conf"
        FileUtils.touch(fcgi_config_fp) if !File.exists?(fcgi_config_fp)
        
        begin
          File.open(fcgi_config_fp) do |fp|
            fp.flock(File::LOCK_EX)
            
            fcgi_config_cont = File.read(fcgi_config_fp)
            
            if !fcgi_config_cont.empty?
              fcgi_config = Marshal.load(File.read(fcgi_config_fp))
              pid = fcgi_config[:pid]
              
              if Knj::Unix_proc.pid_running?(pid)
                fcgi_proxy = fcgi_config
                
                require "http2"
                http = Http2.new(:host => "localhost", :port => fcgi_proxy[:port].to_i)
                fcgi_proxy[:http] = http
              end
            else
              fcgi_config = nil
            end
            
            if !fcgi_proxy
              File.open(fcgi_config_fp, "w") do |fp|
                hayabusa = Hayabusa.new(hayabusa_conf)
                
                #Start web-server for proxy-requests.
                hayabusa.start
                
                fp.write(Marshal.dump(
                  :pid => Process.pid,
                  :port => hayabusa.port
                ))
              end
            end
          end
        ensure
          File.open(fcgi_config_fp).flock(File::LOCK_UN)
        end
      end
      
      
      
      if fcgi_proxy
        #Proxy request to the host-FCGI-process.
        $stderr.puts "[hayabusa] Proxying request." if debug
        cgi_tools.proxy_request_to(:cgi => cgi, :http => fcgi_proxy[:http])
      else
        #Host the FCGI-process.
        $stderr.puts "[hayabusa] Running request as CGI." if debug
        
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
        hayabusa.start_cgi_request
      end
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