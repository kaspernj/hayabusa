#This class is used for FCGI-sessions. It normally starts a Hayabusa-host-process which this (and other) FCGI-processes will proxy requests to. The host-process will automatically kill itself when no more FCGI-sessions are connected to emulate normal FCGI behaviour.
class Hayabusa::Fcgi
  def initialize
    #Spawn CGI-variable to emulate FCGI part.
    @cgi_tools = Hayabusa::Cgi_tools.new
    
    #We cant define the Hayabusa-server untuil we receive the first headers, so wait for the first request.
    @hayabusa = nil
    @hayabusa_fcgi_conf_path = nil
    @fcgi_proxy = nil
    @debug = false
  end
  
  #Evaluates if a new host-process should be started or we should proxy calls to an existing one.
  def evaluate_mode
    #If this is a FCGI-proxy-instance then the HTTP-connection should be checked if it is working.
    if @fcgi_proxy
      if !@fcgi_proxy[:http].socket_working?
        @fcgi_proxy = nil
      end
    end
    
    #Skip the actual check if Hayabusa is spawned or this is a working FCGI-proxy-instance.
    return nil if @hayabusa or @fcgi_proxy
    
    #Parse the configuration-header and generate Hayabusa-config-hash.
    raise "No HTTP_HAYABUSA_FCGI_CONFIG-header was given." if !@cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]
    @hayabusa_fcgi_conf_path = @cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]
    require @hayabusa_fcgi_conf_path
    raise "No 'Hayabusa::FCGI_CONF'-constant was spawned by '#{@cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]}'." if !Hayabusa.const_defined?(:FCGI_CONF)
    conf = Hayabusa::FCGI_CONF
    
    hayabusa_conf = Hayabusa::FCGI_CONF[:hayabusa]
    hayabusa_conf.merge!(
      :cmdline => false,
      :mailing_timeout => 1, #Since FCGI might terminate at any time, try to send out mails almost instantly in the background.
      :port => 0 #Ruby picks random port and we get the actual port after starting the appserver.
    )
    
    #Figure out if this should be a host-FCGI-process or a proxy-FCGI-process.
    fcgi_config_fp = "#{Knj::Os.tmpdir}/hayabusa_fcgi_#{hayabusa_conf[:title]}_fcgi.conf"
    FileUtils.touch(fcgi_config_fp) if !File.exists?(fcgi_config_fp)
    
    File.open(fcgi_config_fp) do |fp|
      fp.flock(File::LOCK_EX)
      
      fcgi_config_cont = File.read(fcgi_config_fp)
      if !fcgi_config_cont.empty?
        #Seems like an instance is already running - check PID to be sure.
        fcgi_config = Marshal.load(File.read(fcgi_config_fp))
        pid = fcgi_config[:pid]
        
        if Knj::Unix_proc.pid_running?(pid)
          #Set this instance to run in proxy-mode.
          begin
            @fcgi_proxy = fcgi_config
            Knj.gem_require(:Http2)
            
            begin
              @fcgi_proxy[:http] = Http2.new(:host => "localhost", :port => @fcgi_proxy[:port].to_i)
            rescue Errno::ECONNREFUSED
              #The host-process has properly closed - evaluate mode again.
              raise Errno::EAGAIN
            end
            
            if hayabusa_conf[:debug]
              @fcgi_proxy[:fp_log] = File.open("/tmp/hayabusa_#{hayabusa_conf[:hayabusa][:title]}_#{Process.pid}.log", "w")
              @fcgi_proxy[:fp_log].sync = true
            end
          rescue
            @fcgi_proxy = nil
            raise
          end
        end
      end
      
      #No instance is already running - start new Hayabusa-instance in both CGI- and socket-mode and write that to the config-file so other instances will register this as the main host-instance.
      if !@fcgi_proxy
        #Spawn sub-process that actually runs the Hayabusa-server.
        require "open3"
        cmd = "#{Knj::Os.executed_executable} #{File.realpath(File.dirname(__FILE__))}/../bin/hayabusa_fcgi_server.rb --conf_path=#{Knj::Strings.unixsafe(@hayabusa_fcgi_conf_path)} --fcgi_data_path=#{Knj::Strings.unixsafe(fcgi_config_fp)}"
        
        #Only used to identify the running FCGI-server host-processes with 'ps aux'.
        cmd << " --title=#{Knj::Strings.unixsafe(hayabusa_conf[:title])}" if hayabusa_conf[:title]
        
        $stderr.puts("Executing command to start FCGI-server: #{cmd}")
        io_out, io_in, io_err = Open3.popen3(cmd)
        
        #Get data that should contain PID and port.
        read = io_in.gets
        raise "Host-process didnt return required data." if !read
        
        #Parse data from the host-process (port and PID).
        begin
          data = Marshal.load(Base64.strict_decode64(read.strip))
        rescue
          raise "Invalid data given from host-process: '#{read}'."
        end
        
        
        #Detach the process where the HTTP-server runs from this process.
        Process.detach(data[:pid])
        
        #Write the data about the new HTTP-server in the config-file and re-evaluate mode. The host-process should not write the file itself, since this process has a lock on that file, and another process might try to start another host-process while writing the file from the host-process, which is not desired.
        File.open(fcgi_config_fp, "w") do |fp|
          fp.write(Marshal.dump(
            :pid => data[:pid],
            :port => data[:port]
          ))
          
          #Started host-process - evaluate mode again and proxy request to the host-process.
          raise Errno::EAGAIN
        end
      end
    end
  end
  
  #Handels the requests comming from the FCGI-object in a loop.
  def fcgi_loop
    $stderr.puts "[hayabusa] Starting FCGI." if @debug
    
    begin
      FCGI.each_cgi do |cgi|
        begin
          #cgi.print "Content-Type: text/html\r\n"
          #cgi.print "\r\n"
          
          #Set 'cgi'-variable for CGI-tools.
          @cgi_tools.cgi = cgi
          @cgi = cgi
          
          #Evaluate the mode of this instance.
          begin
            self.evaluate_mode
          rescue Errno::EAGAIN
            retry
          end
          
          #Ensure the same FCGI-process isnt active for more than one website.
          raise "Expected 'HTTP_HAYABUSA_FCGI_CONFIG' to be '#{@hayabusa_fcgi_conf_path}' but it wasnt: '#{cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]}'." if @hayabusa_fcgi_conf_path and @hayabusa_fcgi_conf_path != cgi.env_table["HTTP_HAYABUSA_FCGI_CONFIG"]
          
          if @fcgi_proxy
            #Proxy request to the host-FCGI-process.
            $stderr.puts "[hayabusa] Proxying request." if @debug
            @cgi_tools.proxy_request_to(:cgi => cgi, :http => @fcgi_proxy[:http], :fp_log => @fcgi_proxy[:fp_log])
          else
            self.handle_fcgi_request(:cgi => cgi)
          end
        rescue Errno::ECONNABORTED, Errno::ECONNREFUSED, Errno::ECONNRESET => e
          $stderr.puts "[hayabusa] Connection to server was interrupted - trying again: <#{e.class.name}> #{e.message}"
          @fcgi_proxy = nil #Force re-evaluate if this process should be host or proxy.
          retry
        rescue Exception => e
          cgi.print "Content-Type: text/html\r\n"
          cgi.print "\r\n"
          cgi.print Knj::Errors.error_str(e, :html => true)
          
          if @hayabusa
            @hayabusa.log_puts e.inspect
            @hayabusa.log_puts e.backtrace
          else
            STDERR.puts e.inspect
            STDERR.puts e.backtrace
          end
        ensure
          @cgi = nil
          @cgi_tools.cgi = nil
        end
      end
    ensure
      $stderr.puts "[hayabusa] FCGI-loop stopped."
      @hayabusa.stop if @hayabusa
    end
  end
  
  #Handles the request as a real request on a Hayabusa-host running inside the current process. This is not used any more but kept if we need support for it once again (maybe the developer should be able to decide this in some kind of config?).
  def handle_fcgi_request(args)
    #Host the FCGI-process.
    $stderr.puts "[hayabusa] Running request as CGI." if @debug
    
    #Enforce $stdout variable.
    $stdout = @hayabusa.cio
    
    #The rest is copied from the FCGI-part.
    headers = {}
    @cgi.env_table.each do |key, val|
      if key[0, 5] == "HTTP_" and key != "HTTP_HAYABUSA_FCGI_CONFIG"
        key = key[5, key.length].gsub("_", " ").gsub(" ", "-")
        headers[key] = val
      end
    end
    
    meta = @cgi.env_table.to_hash
    
    uri = Knj::Web.parse_uri(meta["REQUEST_URI"])
    meta["PATH_TRANSLATED"] = File.basename(uri[:path])
    
    cgi_data = {
      :cgi => @cgi,
      :headers => headers,
      :get => Knj::Web.parse_urlquery(@cgi.env_table["QUERY_STRING"], :urldecode => true, :force_utf8 => true),
      :meta => meta
    }
    if @cgi.request_method == "POST"
      cgi_data[:post] = @cgi_tools.convert_fcgi_post(@cgi.params)
    else
      cgi_data[:post] = {}
    end
    
    @hayabusa.config[:cgi] = cgi_data
    
    
    #Handle request.
    @hayabusa.start_cgi_request
  end
end
