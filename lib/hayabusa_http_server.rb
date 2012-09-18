require "socket"

class Hayabusa::Http_server
  attr_accessor :working_count
  attr_reader :hb, :http_sessions, :thread_accept, :thread_restart, :server
  
  def initialize(hb)
    @hb = hb
    @debug = @hb.config[:debug]
    @mutex_count = Mutex.new
  end
  
  def start
    @http_sessions = []
    @working_count = 0
    
    raise "No host was given." if @hb and !@hb.config.has_key?(:host)
    raise "No port was given." if @hb and !@hb.config.has_key?(:port)
    
    @server = TCPServer.new(@hb.config[:host], @hb.config[:port])
    
    @thread_accept = Thread.new do
      loop do
        begin
          if !@server or @server.closed?
            @hb.log_puts "Starting TCPServer." if @debug
            @server = TCPServer.new(@hb.config[:host], @hb.config[:port])
          end
          
          @hb.log_puts "Trying to spawn new HTTP-session from socket-accept." if @debug
          self.spawn_httpsession(@server.accept)
          @hb.log_puts "Starting new HTTP-request." if @debug
        rescue Exception => e
          if @debug
            @hb.log_puts Knj::Errors.error_str(e)
            @hb.log_puts "Could not accept HTTP-request - waiting 1 sec and then trying again."
          end
          
          raise e if e.is_a?(SystemExit) or e.is_a?(Interrupt)
          sleep 1
        end
      end
    end
  end
  
  def stop
    while @working_count > 0
      @hb.log_puts "Waiting until no HTTP-sessions are running." if @debug
      sleep 0.1
    end
    
    
    @hb.log_puts "Stopping accept-thread." if @debug
    @thread_accept.kill if @thread_accept and @thread_accept.alive?
    @thread_restart.kill if @thread_restart and @thread_restart.alive?
    
    #@hb.log_puts "Stopping all HTTP sessions." if @debug
    #if @http_sessions
    #  @http_sessions.each do |httpsession|
    #    httpsession.destruct
    #  end
    #end
    
    begin
      @hb.log_puts "Stopping TCPServer." if @debug
      @server.close if @server and !@server.closed?
      @hb.log_puts "TCPServer was closed." if @debug
    rescue Timeout::Error
      raise "Could not close TCPserver."
    rescue IOError => e
      if e.message == "closed stream"
        #ignore - it should be closed.
      else
        raise e
      end
    end
    
    @http_sessions = nil
    @thread_accept = nil
    @thread_restart = nil
    @server = nil
    @working_count = nil
    @hb = nil
  end
  
  def spawn_httpsession(socket)
    @hb.log_puts "Starting new HTTP-session." if @debug
    @http_sessions << Hayabusa::Http_session.new(self, socket)
  end
  
  def count_block
    begin
      added = false
      @mutex_count.synchronize do
        @working_count += 1 if @working_count != nil
        added = true
      end
      
      yield
    ensure
      @hb.served += 1 if @hb
      
      @mutex_count.synchronize do
        @working_count -= 1 if @working_count != nil and added
      end
    end
  end
end