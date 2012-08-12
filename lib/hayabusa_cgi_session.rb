class Hayabusa::Cgi_session
  attr_accessor :data, :alert_sent
  attr_reader :cookie, :get, :headers, :session, :session_id, :session_hash, :kas, :active, :out, :eruby, :browser, :debug, :resp, :page_path, :post, :cgroup, :meta, :httpsession_var, :handler, :working
  
  def initialize(args)
    @args = args
    @kas = @args[:kas]
    
    @config = @kas.config
    @handlers_cache = @config[:handlers_cache]
    cgi_conf = @config[:cgi]
    @get, @post, @meta, @headers = cgi_conf[:get], cgi_conf[:post], cgi_conf[:meta], cgi_conf[:headers]
    
    @written_size = 0
    @size_send = @config[:size_send]
    
    @eruby = Knj::Eruby.new(
      :cache_hash => @kas.eruby_cache,
      :binding_callback => self.method(:create_binding)
    )
    
    Thread.current[:hayabusa] = {
      :kas => @kas,
      :httpsession => self,
      :session => @session,
      :get => @get,
      :post => @post,
      :meta => @meta,
      :cookie => @cookie
    }
    
    
    #Parse URI (page_path and get).
    match = @meta["SERVER_PROTOCOL"].match(/^HTTP\/1\.(\d+)\s*/)
    raise "Could match HTTP-protocol from: '#{@meta["SERVER_PROTOCOL"]}'." if !match
    http_version = "1.#{match[1]}"
    
    
    @page_path = @meta["PATH_TRANSLATED"]
    @ext = File.extname(@page_path).downcase[1..-1].to_s
    
    @resp = Hayabusa::Http_session::Response.new(:socket => self)
    @resp.reset(:http_version => http_version, :mode => :cgi)
    @resp.header("Content-Type", "text/html")
    
    @cgroup = Hayabusa::Http_session::Contentgroup.new(:socket => self, :kas => @kas, :resp => @resp, :httpsession => self)
    @cgroup.reset
    
    @resp.cgroup = @cgroup
    
    begin
      @kas.events.call(:request_begin, :httpsession => self) if @kas.events
      
      Timeout.timeout(@kas.config[:timeout]) do
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
      
      @kas.events.call(:request_done, {
        :httpsession => self
      }) if @kas.events
    rescue SystemExit
      #do nothing - ignore.
    rescue Timeout::Error
      @resp.status = 500
      print "The request timed out."
    end
  end
  
  #Creates a new Hayabusa::Binding-object and returns the binding for that object.
  def create_binding
    return Hayabusa::Http_session::Page_environment.new(:httpsession => self, :kas => @kas).get_binding
  end
  
  #Is called when content is added and begings to write the output if it goes above the limit.
  def add_size(size)
    @written_size += size
    @cgroup.write_output if @written_size >= @size_send
  end
  
  #Called from content-group.
  def write(str)
    print str
  end
end