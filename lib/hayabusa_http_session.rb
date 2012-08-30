#This class handels the HTTP-sessions.
class Hayabusa::Http_session
  attr_accessor :data, :alert_sent
  attr_reader :cookie, :get, :headers, :ip, :session, :session_id, :session_hash, :hb, :active, :out, :eruby, :browser, :debug, :resp, :page_path, :post, :cgroup, :meta, :httpsession_var, :handler, :working
  
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
    @hb = httpserver.hb
    @types = @hb.types
    @config = @hb.config
    @active = true
    @debug = @hb.debug
    @handlers_cache = @config[:handlers_cache]
    @httpsession_var = {}
    
    @eruby = Knj::Eruby.new(
      :cache_hash => @hb.eruby_cache,
      :binding_callback => self.method(:create_binding)
    )
    
    #Set socket stuff.
    if RUBY_PLATFORM == "java" or RUBY_ENGINE == "rbx"
      if @hb.config[:peeraddr_static]
        addr_peer = [0, 0, @hb.config[:peeraddr_static]]
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
    @handler = Hayabusa::Http_session::Request.new(:hb => @hb, :httpsession => self)
    @cgroup = Hayabusa::Http_session::Contentgroup.new(:socket => @socket, :hb => @hb, :resp => @resp, :httpsession => self)
    @resp.cgroup = @cgroup
    
    Dir.chdir(@config[:doc_root])
    ObjectSpace.define_finalizer(self, self.class.method(:finalize).to_proc) if @debug
    @hb.log_puts "New httpsession #{self.__id__} (total: #{@httpserver.http_sessions.count})." if @debug
    
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
          break if @hb.should_restart
          
          @hb.log_puts "#{__id__} - Waiting to parse from socket." if @debug
          Timeout.timeout(1800) do
            @handler.socket_parse(@socket)
          end
          
          @hb.log_puts "#{__id__} - Done parsing from socket." if @debug
          
          while @hb.paused? #Check if we should be waiting with executing the pending request.
            @hb.log_puts "#{__id__} - Paused! (#{@hb.paused}) - sleeping." if @debug
            sleep 0.1
          end
          
          break if @hb.should_restart
          
          if max_requests_working and @httpserver
            while @httpserver.working_count.to_i >= max_requests_working
              @hb.log_puts "#{__id__} - Maximum amounts of requests are working (#{@httpserver.working_count}, #{max_requests_working}) - sleeping." if @debug
              sleep 0.1
            end
          end
          
          #Reserve database connections.
          @hb.db_handler.get_and_register_thread if @hb.db_handler.opts[:threadsafe]
          @hb.ob.db.get_and_register_thread if @hb.ob.db.opts[:threadsafe]
          
          @working = true
          @hb.log_puts "#{__id__} - Serving." if @debug
          
          @httpserver.count_block do
            self.serve
          end
        ensure
          @hb.log_puts "#{__id__} - Closing request." if @debug
          @working = false
          
          #Free reserved database-connections.
          @hb.db_handler.free_thread if @hb and @hb.db_handler.opts[:threadsafe]
          @hb.ob.db.free_thread if @hb and @hb.ob.db.opts[:threadsafe]
        end
      end
    rescue Timeout::Error
      @hb.log_puts "#{__id__} - Closing httpsession because of timeout." if @debug
    rescue Errno::ECONNRESET, Errno::ENOTCONN, Errno::EPIPE => e
      @hb.log_puts "#{__id__} - Connection error (#{e.inspect})..." if @debug
      @hb.log_puts e.backtrace
    rescue Interrupt => e
      raise e
    rescue Exception => e
      @hb.log_puts Knj::Errors.error_str(e)
    ensure
      self.destruct
    end
  end
  
  #Creates a new Hayabusa::Binding-object and returns the binding for that object.
  def create_binding
    binding_obj = Hayabusa::Http_session::Page_environment.new(:httpsession => self, :hb => @hb)
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
    Thread.current[:hayabusa] = {} if !Thread.current[:hayabusa]
    Thread.current[:hayabusa][:hb] = @hb
    Thread.current[:hayabusa][:httpsession] = self
    Thread.current[:hayabusa][:session] = @session
    Thread.current[:hayabusa][:get] = @get
    Thread.current[:hayabusa][:post] = @post
    Thread.current[:hayabusa][:meta] = @meta
    Thread.current[:hayabusa][:cookie] = @cookie
  end
  
  def self.finalize(id)
    @hb.log_puts "Http_session finalize #{id}." if @debug
  end
  
  def destruct
    @hb.log_puts "Http_session destruct (#{@httpserver.http_sessions.length})" if @debug and @httpserver and @httpserver.http_sessions
    
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
    @hb.log_puts "Generating meta, cookie, get, post and headers." if @debug
    @meta = @handler.meta.merge(@socket_meta)
    @cookie = @handler.cookie
    @get = @handler.get
    @post = @handler.post
    @headers = @handler.headers
    
    close = true if @meta["HTTP_CONNECTION"] == "close"
    @resp.reset(
      :http_version => @handler.http_version,
      :close => close,
      :cookie => @cookie
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
    @ip = @hb.ip(:meta => @meta)
    
    @hb.log_puts "Figuring out session-ID, session-object and more." if @debug
    if @cookie["HayabusaSession"].to_s.length > 0
      @session_id = @cookie["HayabusaSession"]
    elsif @browser["browser"] == "bot"
      @session_id = "bot"
    else
      @session_id = @hb.session_generate_id(@meta)
      send_cookie = true
    end
    
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
    
    if @config.key?(:logging) and @config[:logging][:access_db]
      @hb.log_puts "Doing access-logging." if @debug
      @ips = [@meta["REMOTE_ADDR"]]
      @ips << @meta["HTTP_X_FORWARDED_FOR"].split(",")[0].strip if @meta["HTTP_X_FORWARDED_FOR"]
      @hb.logs_access_pending << {
        :session_id => @session.id,
        :date_request => Time.now,
        :ips => @ips,
        :get => @get,
        :post => @post,
        :meta => @meta,
        :cookie => @cookie
      }
    end
    
    @hb.log_puts "Initializing thread and content-group." if @debug
    self.init_thread
    Thread.current[:hayabusa][:contentgroup] = @cgroup
    time_start = Time.now.to_f if @debug
    
    begin
      @hb.events.call(:request_begin, :httpsession => self) if @hb.events
      
      Timeout.timeout(@hb.config[:timeout]) do
        if @handlers_cache.key?(@ext)
          @hb.log_puts "Calling handler." if @debug
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
    @hb.log_puts "#{__id__} - Served '#{@meta["REQUEST_URI"]}' in #{Time.now.to_f - time_start} secs (#{@resp.status})." if @debug
    @cgroup.join
    
    @hb.events.call(:request_done, {
      :httpsession => self
    }) if @hb.events
    @httpsession_var = {}
  end
end