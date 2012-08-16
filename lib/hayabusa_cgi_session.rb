class Hayabusa::Cgi_session
  attr_accessor :data, :alert_sent
  attr_reader :cookie, :get, :headers, :session, :session_id, :session_hash, :hb, :active, :out, :eruby, :browser, :debug, :resp, :page_path, :post, :cgroup, :meta, :httpsession_var, :handler, :working
  
  def initialize(args)
    @args = args
    @hb = @args[:hb]
    
    @config = @hb.config
    @handlers_cache = @config[:handlers_cache]
    cgi_conf = @config[:cgi]
    @get, @post, @meta, @headers = cgi_conf[:get], cgi_conf[:post], cgi_conf[:meta], cgi_conf[:headers]
    
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
    @ext = File.extname(@page_path).downcase[1..-1].to_s
    
    @resp = Hayabusa::Http_session::Response.new(:socket => self)
    @resp.reset(:http_version => http_version, :mode => :cgi)
    @resp.header("Content-Type", "text/html")
    
    @cgroup = Hayabusa::Http_session::Contentgroup.new(:socket => self, :hb => @hb, :resp => @resp, :httpsession => self)
    @cgroup.reset
    
    @resp.cgroup = @cgroup
    
    begin
      @hb.events.call(:request_begin, :httpsession => self) if @hb.events
      
      Timeout.timeout(@hb.config[:timeout]) do
        if @handlers_cache.key?(@ext)
          STDOUT.print "Calling handler.\n" if @debug
          @handlers_cache[@ext].call(self)
        else
          raise "CGI-mode shouldnt serve static files."
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
      :session => @session,
      :get => @get,
      :post => @post,
      :meta => @meta,
      :cookie => @cookie
    }
  end
end