class Hayabusa::Cgi_session
  attr_accessor :data, :alert_sent
  attr_reader :cookie, :get, :headers, :session, :session_id, :session_hash, :hb, :active, :out, :eruby, :browser, :debug, :resp, :page_path, :post, :cgroup, :meta, :httpsession_var, :working
  
  def initialize(args)
    @args = args
    @hb = @args[:hb]
    
    @config = @hb.config
    @handlers_cache = @config[:handlers_cache]
    cgi_conf = @config[:cgi]
    @get, @post, @meta, @headers = cgi_conf[:get], cgi_conf[:post], cgi_conf[:meta], cgi_conf[:headers]
    @browser = Knj::Web.browser(@meta)
    
    #Parse cookies and other headers.
    @cookie = {}
    @headers.each do |key, val|
      #$stderr.puts "Header-Key: '#{key}'."
      
      case key
        when "COOKIE"
          Knj::Web.parse_cookies(val).each do |key, val|
            @cookie[key] = val
          end
      end
    end
    
    
    #Set up the 'out', 'written_size' and 'size_send' variables which is used to write output.
    if cgi_conf[:cgi]
      @out = cgi_conf[:cgi]
    else
      @out = $stdout
    end
    
    @written_size = 0
    @size_send = @config[:size_send]
    
    @eruby = Knj::Eruby.new(
      :cache_hash => @hb.eruby_cache,
      :binding_callback => self.method(:create_binding)
    )
    
    self.init_thread
    
    
    #Parse URI (page_path and get).
    match = @meta["SERVER_PROTOCOL"].match(/^HTTP\/1\.(\d+)\s*/)
    raise "Could match HTTP-protocol from: '#{@meta["SERVER_PROTOCOL"]}'." if !match
    http_version = "1.#{match[1]}"
    
    
    Dir.chdir(@config[:doc_root])
    @page_path = @meta["PATH_TRANSLATED"]
    @page_path = "index.rhtml" if @page_path == "/"
    
    @ext = File.extname(@page_path).downcase[1..-1].to_s
    
    @resp = Hayabusa::Http_session::Response.new(:socket => self)
    @resp.reset(:http_version => http_version, :mode => :cgi, :cookie => @cookie)
    
    @cgroup = Hayabusa::Http_session::Contentgroup.new(:socket => self, :hb => @hb, :resp => @resp, :httpsession => self)
    @cgroup.reset
    
    @resp.cgroup = @cgroup
    @resp.header("Content-Type", "text/html")
    
    
    #Set up session-variables.
    if !@cookie["HayabusaSession"].to_s.empty?
      @session_id = @cookie["HayabusaSession"]
    elsif @browser["browser"] == "bot"
      @session_id = "bot"
    else
      @session_id = @hb.session_generate_id(@meta)
      send_cookie = true
    end
    
    #Set the 'ip'-variable which is required for sessions.
    @ip = @meta["REMOTE_ADDR"]
    raise "No 'ip'-variable was set: '#{@meta}'." if !@ip
    raise "'session_id' was not valid." if @session_id.to_s.strip.empty?
    
    begin
      @session, @session_hash = @hb.session_fromid(@ip, @session_id, @meta)
    rescue ArgumentError => e
      #User should not have the session he asked for because of invalid user-agent or invalid IP.
      @session_id = @hb.session_generate_id(@meta)
      @session, @session_hash = @hb.session_fromid(@ip, @session_id, @meta)
      send_cookie = true
    end
    
    if send_cookie
      @resp.cookie(
        "name" => "HayabusaSession",
        "value" => @session_id,
        "path" => "/",
        "expires" => Time.now + 32140800 #add around 12 months
      )
    end
    
    raise "'session'-variable could not be spawned." if !@session
    raise "'session_hash'-variable could not be spawned." if !@session_hash
    Thread.current[:hayabusa][:session] = @session
    
    
    begin
      @hb.events.call(:request_begin, :httpsession => self) if @hb.events
      
      Timeout.timeout(@hb.config[:timeout]) do
        if @handlers_cache.key?(@ext)
          @hb.log_puts "Calling handler." if @debug
          @handlers_cache[@ext].call(self)
        else
          raise "CGI-mode shouldnt serve static files: '#{@page_path}'."
        end
      end
      
      @cgroup.mark_done
      @cgroup.write_output
      @cgroup.join
      
      @hb.events.call(:request_done, {
        :httpsession => self
      }) if @hb.events
    rescue SystemExit
      #do nothing - ignore.
    rescue Timeout::Error
      @resp.status = 500
      print "The request timed out."
    end
  end
  
  def handler
    return self
  end
  
  #Parses the if-modified-since header and returns it as a Time-object. Returns false is no if-modified-since-header is given or raises an RuntimeError if it cant be parsed.
  def modified_since
    return @modified_since if @modified_since
    return false if !@meta["HTTP_IF_MODIFIED_SINCE"]
    
    mod_match = @meta["HTTP_IF_MODIFIED_SINCE"].match(/^([A-z]+),\s+(\d+)\s+([A-z]+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(.+)$/)
    raise "Could not parse 'HTTP_IF_MODIFIED_SINCE'." if !mod_match
    
    month_no = Datet.month_str_to_no(mod_match[3])
    @modified_since = Time.utc(mod_match[4].to_i, month_no, mod_match[2].to_i, mod_match[5].to_i, mod_match[6].to_i, mod_match[7].to_i)
    
    return @modified_since
  end
  
  #Forces the content to be the input - nothing else can be added after calling this.
  def force_content(newcont)
    @cgroup.force_content(newcont)
  end
  
  #Creates a new Hayabusa::Binding-object and returns the binding for that object.
  def create_binding
    return Hayabusa::Http_session::Page_environment.new(:httpsession => self, :hb => @hb).get_binding
  end
  
  #Is called when content is added and begings to write the output if it goes above the limit.
  def add_size(size)
    @written_size += size
    @cgroup.write_output if @written_size >= @size_send
  end
  
  #Called from content-group.
  def write(str)
    @out.print(str)
  end
  
  def threadded_content(block)
    raise "No block was given." if !block
    cgroup = Thread.current[:hayabusa][:contentgroup].new_thread
    
    Thread.new do
      begin
        self.init_thread
        cgroup.register_thread
        
        @hb.db_handler.get_and_register_thread if @hb and @hb.db_handler.opts[:threadsafe]
        @hb.ob.db.get_and_register_thread if @hb and @hb.ob.db.opts[:threadsafe]
        
        block.call
      rescue Exception => e
        Thread.current[:hayabusa][:contentgroup].write Knj::Errors.error_str(e, {:html => true})
        _hb.handle_error(e)
      ensure
        Thread.current[:hayabusa][:contentgroup].mark_done
        @hb.ob.db.free_thread if @hb and @hb.ob.db.opts[:threadsafe]
        @hb.db_handler.free_thread if @hb and @hb.db_handler.opts[:threadsafe]
      end
    end
  end
  
  def init_thread
    Thread.current[:hayabusa] = {
      :hb => @hb,
      :httpsession => self,
      :get => @get,
      :post => @post,
      :meta => @meta,
      :cookie => @cookie
    }
  end
end