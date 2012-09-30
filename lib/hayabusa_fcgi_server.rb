#This class is used to start Hayabusa in its own process, which FCGI-sessions then connects to. This way only one instance of Hayabusa is actually running to allowed FCGI-sessions to "commuicate" with each other (because they are running in the same process).
class Hayabusa::Fcgi_server
  attr_reader :hayabusa
  
  def initialize(args)
    #Start web-server for proxy-requests.
    @hayabusa = Hayabusa.new(args[:hayabusa_conf])
    @hayabusa.start
    
    #In FCGI-mode the host-process should exit when zero FCGI-connections are active.
    @hayabusa.events.connect(:http_session_destruct, &self.method(:on_http_session_destruct))
  end
  
  #Called when a HTTP-session destructs (disconnects). Used to stop the Hayabusa-appserver when no connections are active to only be running when FCGI-sessions are running.
  def on_http_session_destruct(*args)
    @hayabusa.log_puts("HTTP-connection destruction - checking if no connections are active any more.")
    
    stop = false
    httpserv = @hayabusa.httpserv
    
    if !httpserv or !httpserv.http_sessions or httpserv.http_sessions.empty?
      stop = true
    end
    
    if stop
      @hayabusa.log_puts("Stopping server because no active connections.")
      @hayabusa.stop
    end
  end
end