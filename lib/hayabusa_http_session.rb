#This class handels the HTTP-sessions.
class Hayabusa::Http_session
  attr_accessor :data, :alert_sent
  attr_reader :cookie, :get, :headers, :session, :session_id, :session_hash, :kas, :active, :out, :eruby, :browser, :debug, :resp, :page_path, :post, :cgroup, :meta, :httpsession_var, :handler, :working
  
  #Autoloader for subclasses.
  def self.const_missing(name)
    require "#{File.dirname(__FILE__)}/hayabusa_http_session_#{name.to_s.downcase}.rb"
    raise "Still not defined: '#{name}'." if !Hayabusa::Http_session.const_defined?(name)
    return Hayabusa::Http_session.const_get(name.to_s.to_sym)
  end
  
  def initialize(httpserver, socket)
    @data = {}
    @socket = socket
    @httpserver = httpserver
    @kas = httpserver.kas
    @types = @kas.types
    @config = @kas.config
    @active = true
    @debug = @kas.debug
    @handlers_cache = @config[:handlers_cache]
    @httpsession_var = {}
    
    @eruby = Knj::Eruby.new(
      :cache_hash => @kas.eruby_cache,
      :binding_callback => self.method(:create_binding)
    )
    
    #Set socket stuff.
    if RUBY_PLATFORM == "java" or RUBY_ENGINE == "rbx"
      if @kas.config[:peeraddr_static]
        addr_peer = [0, 0, @kas.config[:peeraddr_static]]
      else
        addr_peer = @socket.peeraddr
      end
      
      addr = @socket.addr
    else
      addr = @socket.addr(false)
      addr_peer = @socket.peeraddr(false)
    end
    
    @socket_meta = {
      "REMOTE_ADDR" => addr[2],
      "REMOTE_PORT" => addr[1],
      "SERVER_ADDR" => addr_peer[2],
      "SERVER_PORT" => addr_peer[1]
    }
    
    @resp = Hayabusa::Http_session::Response.new(:socket => @socket)
    @handler = Hayabusa::Http_session::Request.new(:kas => @kas, :httpsession => self)
    @cgroup = Hayabusa::Http_session::Contentgroup.new(:socket => @socket, :kas => @kas, :resp => @resp, :httpsession => self)
    @resp.cgroup = @cgroup
    
    Dir.chdir(@config[:doc_root])
    ObjectSpace.define_finalizer(self, self.class.method(:finalize).to_proc) if @debug
    STDOUT.print "New httpsession #{self.__id__} (total: #{@httpserver.http_sessions.count}).\n" if @debug
    
    @thread_request = Thread.new(&self.method(:thread_request_run))
  end
  
  def thread_request_run
    Thread.current[:hayabusa] = {} if !Thread.current[:hayabusa]
    Thread.current[:type] = :httpsession
    
    if @config.key?(:max_requests_working)
      max_requests_working = @config[:max_requests_working].to_i
    else
      max_requests_working = false
    end
    
    begin
      while @active
        begin
          @cgroup.reset
          @written_size = 0
          @size_send = @config[:size_send]
          @alert_sent = false
          @working = false
          break if @kas.should_restart
          
          STDOUT.print "#{__id__} - Waiting to parse from socket.\n" if @debug
          Timeout.timeout(1800) do
            @handler.socket_parse(@socket)
          end
          
          STDOUT.print "#{__id__} - Done parsing from socket.\n" if @debug
          
          while @kas.paused? #Check if we should be waiting with executing the pending request.
            STDOUT.print "#{__id__} - Paused! (#{@kas.paused}) - sleeping.\n" if @debug
            sleep 0.1
          end
          
          break if @kas.should_restart
          
          if max_requests_working and @httpserver
            while @httpserver.working_count.to_i >= max_requests_working
              STDOUT.print "#{__id__} - Maximum amounts of requests are working (#{@httpserver.working_count}, #{max_requests_working}) - sleeping.\n" if @debug
              sleep 0.1
            end
          end
          
          #Reserve database connections.
          @kas.db_handler.get_and_register_thread if @kas.db_handler.opts[:threadsafe]
          @kas.ob.db.get_and_register_thread if @kas.ob.db.opts[:threadsafe]
          
          @working = true
          STDOUT.print "#{__id__} - Serving.\n" if @debug
          
          @httpserver.count_block do
            self.serve
          end
        ensure
          STDOUT.print "#{__id__} - Closing request.\n" if @debug
          @working = false
          
          #Free reserved database-connections.
          @kas.db_handler.free_thread if @kas and @kas.db_handler.opts[:threadsafe]
          @kas.ob.db.free_thread if @kas and @kas.ob.db.opts[:threadsafe]
        end
      end
    rescue Timeout::Error
      STDOUT.print "#{__id__} - Closing httpsession because of timeout.\n" if @debug
    rescue Errno::ECONNRESET, Errno::ENOTCONN, Errno::EPIPE => e
      STDOUT.print "#{__id__} - Connection error (#{e.inspect})...\n" if @debug
    rescue Interrupt => e
      raise e
    rescue Exception => e
      STDOUT.puts Knj::Errors.error_str(e)
    ensure
      self.destruct
    end
  end
  
  #Creates a new Hayabusa::Binding-object and returns the binding for that object.
  def create_binding
    binding_obj = Hayabusa::Http_session::Page_environment.new(:httpsession => self, :kas => @kas)
    return binding_obj.get_binding
  end
  
  #Is called when content is added and begings to write the output if it goes above the limit.
  def add_size(size)
    @written_size += size
    @cgroup.write_output if @written_size >= @size_send
  end
  
  def threadded_content(block)
    raise "No block was given." if !block
    cgroup = Thread.current[:hayabusa][:contentgroup].new_thread
    
    Thread.new do
      begin
        self.init_thread
        cgroup.register_thread
        
        @kas.db_handler.get_and_register_thread if @kas and @kas.db_handler.opts[:threadsafe]
        @kas.ob.db.get_and_register_thread if @kas and @kas.ob.db.opts[:threadsafe]
        
        block.call
      rescue Exception => e
        Thread.current[:hayabusa][:contentgroup].write Knj::Errors.error_str(e, {:html => true})
        _kas.handle_error(e)
      ensure
        Thread.current[:hayabusa][:contentgroup].mark_done
        @kas.ob.db.free_thread if @kas and @kas.ob.db.opts[:threadsafe]
        @kas.db_handler.free_thread if @kas and @kas.db_handler.opts[:threadsafe]
      end
    end
  end
  
  def init_thread
    Thread.current[:hayabusa] = {} if !Thread.current[:hayabusa]
    Thread.current[:hayabusa][:kas] = @kas
    Thread.current[:hayabusa][:httpsession] = self
    Thread.current[:hayabusa][:session] = @session
    Thread.current[:hayabusa][:get] = @get
    Thread.current[:hayabusa][:post] = @post
    Thread.current[:hayabusa][:meta] = @meta
    Thread.current[:hayabusa][:cookie] = @cookie
  end
  
  def self.finalize(id)
    STDOUT.print "Http_session finalize #{id}.\n" if @debug
  end
  
  def destruct
    STDOUT.print "Http_session destruct (#{@httpserver.http_sessions.length})\n" if @debug and @httpserver and @httpserver.http_sessions
    
    begin
      @socket.close if !@socket.closed?
    rescue => e
      STDOUT.puts e.inspect
      STDOUT.puts e.backtrace
      #ignore if it fails...
    end
    
    @httpserver.http_sessions.delete(self) if @httpserver and @httpserver.http_sessions
    
    @eruby.destroy if @eruby
    @thread_request.kill if @thread_request.alive?
  end
  
  #Forces the content to be the input - nothing else can be added after calling this.
  def force_content(newcont)
    @cgroup.force_content(newcont)
  end
  
  def serve
    STDOUT.print "Generating meta, cookie, get, post and headers.\n" if @debug
    @meta = @handler.meta.merge(@socket_meta)
    @cookie = @handler.cookie
    @get = @handler.get
    @post = @handler.post
    @headers = @handler.headers
    
    close = true if @meta["HTTP_CONNECTION"] == "close"
    @resp.reset(
      :http_version => @handler.http_version,
      :close => close
    )
    if @handler.http_version == "1.1"
      @cgroup.chunked = true
      @resp.chunked = true
    else
      @cgroup.chunked = false
      @resp.chunked = false
    end
    
    @page_path = @handler.page_path
    @ext = File.extname(@page_path).downcase[1..-1].to_s
    
    @ctype = @types[@ext.to_sym] if @ext.length > 0 and @types.key?(@ext.to_sym)
    @ctype = @config[:default_filetype] if !@ctype and @config.key?(:default_filetype)
    @resp.header("Content-Type", @ctype)
    
    @browser = Knj::Web.browser(@meta)
    
    if @meta["HTTP_X_FORWARDED_FOR"]
      @ip = @meta["HTTP_X_FORWARDED_FOR"].split(",")[0].strip
    elsif @meta["REMOTE_ADDR"]
      @ip = @meta["REMOTE_ADDR"]
    else
      raise "Could not figure out the IP of the session."
    end
    
    STDOUT.print "Figuring out session-ID, session-object and more.\n" if @debug
    if @cookie["HayabusaSession"].to_s.length > 0
      @session_id = @cookie["HayabusaSession"]
    elsif @browser["browser"] == "bot"
      @session_id = "bot"
    else
      @session_id = @kas.session_generate_id(@meta)
      send_cookie = true
    end
    
    begin
      @session, @session_hash = @kas.session_fromid(@ip, @session_id, @meta)
    rescue ArgumentError => e
      #User should not have the session he asked for because of invalid user-agent or invalid IP.
      @session_id = @kas.session_generate_id(@meta)
      @session, @session_hash = @kas.session_fromid(@ip, @session_id, @meta)
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
    
    if @config.key?(:logging) and @config[:logging][:access_db]
      STDOUT.print "Doing access-logging.\n" if @debug
      @ips = [@meta["REMOTE_ADDR"]]
      @ips << @meta["HTTP_X_FORWARDED_FOR"].split(",")[0].strip if @meta["HTTP_X_FORWARDED_FOR"]
      @kas.logs_access_pending << {
        :session_id => @session.id,
        :date_request => Time.now,
        :ips => @ips,
        :get => @get,
        :post => @post,
        :meta => @meta,
        :cookie => @cookie
      }
    end
    
    STDOUT.print "Initializing thread and content-group.\n" if @debug
    self.init_thread
    Thread.current[:hayabusa][:contentgroup] = @cgroup
    time_start = Time.now.to_f if @debug
    
    begin
      @kas.events.call(:request_begin, :httpsession => self) if @kas.events
      
      Timeout.timeout(@kas.config[:timeout]) do
        if @handlers_cache.key?(@ext)
          STDOUT.print "Calling handler.\n" if @debug
          @handlers_cache[@ext].call(self)
        else
          #check if we should use a handler for this request.
          @config[:handlers].each do |handler_info|
            if handler_info.key?(:file_ext) and handler_info[:file_ext] == @ext
              return handler_info[:callback].call(self)
            elsif handler_info.key?(:path) and handler_info[:mount] and @meta["SCRIPT_NAME"].slice(0, handler_info[:path].length) == handler_info[:path]
              @page_path = "#{handler_info[:mount]}#{@meta["SCRIPT_NAME"].slice(handler_info[:path].length, @meta["SCRIPT_NAME"].length)}"
              break
            end
          end
          
          if !File.exists?(@page_path)
            @resp.status = 404
            @resp.header("Content-Type", "text/html")
            @cgroup.write("File you are looking for was not found: '#{@meta["REQUEST_URI"]}'.")
          else
            if @headers["cache-control"] and @headers["cache-control"][0]
              cache_control = {}
              @headers["cache-control"][0].scan(/(.+)=(.+)/) do |match|
                cache_control[match[1]] = match[2]
              end
            end
            
            cache_dont = true if cache_control and cache_control.key?("max-age") and cache_control["max-age"].to_i <= 0
            lastmod = File.mtime(@page_path)
            
            @resp.header("Last-Modified", lastmod.httpdate)
            @resp.header("Expires", (Time.now + 86400).httpdate) #next day.
            
            if !cache_dont and @headers["if-modified-since"] and @headers["if-modified-since"][0]
              request_mod = Datet.in(@headers["if-modified-since"].first).time
              
              if request_mod == lastmod
                @resp.status = 304
                return nil
              end
            end
            
            @cgroup.new_io(:type => :file, :path => @page_path)
          end
        end
      end
    rescue SystemExit
      #do nothing - ignore.
    rescue Timeout::Error
      @resp.status = 500
      print "The request timed out."
    end
    
    @cgroup.mark_done
    @cgroup.write_output
    STDOUT.print "#{__id__} - Served '#{@meta["REQUEST_URI"]}' in #{Time.now.to_f - time_start} secs (#{@resp.status}).\n" if @debug
    @cgroup.join
    
    @kas.events.call(:request_done, {
      :httpsession => self
    }) if @kas.events
    @httpsession_var = {}
  end
end