class Hayabusa::Cgi_session < Hayabusa::Client_session
  attr_accessor :alert_sent, :data, :page_path
  attr_reader :cookie, :get, :headers, :ip, :session, :session_id, :session_hash, :hb, :active, :out, :eruby, :browser, :debug, :resp, :post, :cgroup, :meta, :httpsession_var, :working

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
    @out = cgi_conf[:cgi] || $stdout
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
    @ip = @hb.ip(:meta => @meta)
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
      self.execute_page
      self.execute_done
    rescue SystemExit
      #do nothing - ignore.
    rescue Timeout::Error
      @resp.status = 408
    end
  end

  def handler
    return self
  end
end