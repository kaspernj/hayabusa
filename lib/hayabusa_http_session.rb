#This class handels the HTTP-sessions.
class Hayabusa::Http_session < Hayabusa::Client_session
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
    
    @resp = Hayabusa::Http_session::Response.new(:hb => @hb, :socket => @socket)
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
          
          begin
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
            @handler.delete_tempfiles
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
      @hb.log_puts e.backtrace if @debug
    rescue Interrupt => e
      raise e
    rescue Exception => e
      @hb.log_puts Knj::Errors.error_str(e)
    ensure
      self.destruct
    end
  end
  
  def self.finalize(id)
    @hb.log_puts "Hayabusa: Http_session finalize #{id}." if @debug
  end
  
  def destruct
    @hb.log_puts "Hayabusa: Http_session destruct (#{@httpserver.http_sessions.length})" if @debug and @httpserver and @httpserver.http_sessions
    
    begin
      @socket.close if !@socket.closed?
    rescue => e
      @hb.log_puts(e.inspect)
      @hb.log_puts(e.backtrace)
      #ignore if it fails...
    end
    
    @httpserver.http_sessions.delete(self) if @httpserver and @httpserver.http_sessions
    @eruby.destroy if @eruby
    @hb.events.call(:http_session_destruct, :httpsession => self) if @hb.events
    @thread_request.kill if @thread_request.alive?
  end
  
  def serve
    @hb.log_puts "Hayabusa: Generating meta, cookie, get, post and headers." if @debug
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
    
    @hb.log_puts "Hayabusa: Figuring out session-ID, session-object and more." if @debug
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
        "expires" => Time.now + 32140800 #add around 12 months from the current time
      )
    end
    
    if @config.key?(:logging) and @config[:logging][:access_db]
      @hb.log_puts "Hayabusa: Doing access-logging." if @debug
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
    
    self.execute_page
    self.execute_done
  end
end