#Various client-sessions should extend this class.
class Hayabusa::Client_session
  attr_accessor :alert_sent, :data, :page_path
  attr_reader :cookie, :get, :handler, :headers, :ip, :session, :session_id, :session_hash, :hb, :active, :out, :eruby, :browser, :debug, :resp, :post, :cgroup, :meta, :httpsession_var, :working, :request_hash

  #Parses the if-modified-since header and returns it as a Time-object. Returns false is no if-modified-since-header is given or raises an RuntimeError if it cant be parsed.
  def modified_since
    return @modified_since if @modified_since
    return false if !@meta["HTTP_IF_MODIFIED_SINCE"]

    mod_match = @meta["HTTP_IF_MODIFIED_SINCE"].match(/^([A-Za-z]+),\s+(\d+)\s+([A-Za-z]+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(.+)$/)
    raise "Could not parse 'HTTP_IF_MODIFIED_SINCE'." if !mod_match

    month_no = Datet.month_str_to_no(mod_match[3])
    @modified_since = Time.utc(mod_match[4].to_i, month_no, mod_match[2].to_i, mod_match[5].to_i, mod_match[6].to_i, mod_match[7].to_i)

    return @modified_since
  end

  #Forces the content to be the input - nothing else can be added after calling this.
  def force_content(newcont)
    @cgroup.force_content(newcont)
  end

  #Forces the output to be read from a file.
  def force_fileread(fpath)
    raise "Invalid filepath given: '#{fpath}'." if !fpath || !File.exist?(fpath)
    @resp.chunked = false
    @resp.header("Content-Length", File.size(fpath))
    @cgroup.new_io(:type => :file, :path => fpath)
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
    Thread.current[:hayabusa] = {} if !Thread.current[:hayabusa]
    Thread.current[:hayabusa][:hb] = @hb
    Thread.current[:hayabusa][:httpsession] = self
    Thread.current[:hayabusa][:session] = @session
    Thread.current[:hayabusa][:get] = @get
    Thread.current[:hayabusa][:post] = @post
    Thread.current[:hayabusa][:meta] = @meta
    Thread.current[:hayabusa][:cookie] = @cookie
  end

  def execute_page
    @request_hash = {}

    begin
      @time_start = Time.now.to_f if @debug
      @hb.events.call(:request_begin, :httpsession => self) if @hb.events

      Timeout.timeout(@hb.config[:timeout]) do
        if @handlers_cache.key?(@ext)
          @hb.log_puts("Calling handler.") if @debug
          @handlers_cache[@ext].call(self)
          @hb.log_puts("Called handler.") if @debug
        else
          #check if we should use a handler for this request.
          @config[:handlers].each do |handler_info|
            if handler_info.key?(:file_ext) and handler_info[:file_ext] == @ext
              handler_info[:callback].call(self)
              break
            elsif handler_info.key?(:path) and handler_info[:mount] and @meta["SCRIPT_NAME"].slice(0, handler_info[:path].length) == handler_info[:path]
              @page_path = "#{handler_info[:mount]}#{@meta["SCRIPT_NAME"].slice(handler_info[:path].length, @meta["SCRIPT_NAME"].length)}"
              break
            elsif handler_info.key?(:regex) and @meta["REQUEST_URI"].to_s.match(handler_info[:regex])
              handler_info[:callback].call(:httpsession => self)
              break
            end
          end

          if @page_path
            if !File.exist?(@page_path)
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

              self.force_fileread(@page_path)
            end
          end
        end
      end
    rescue SystemExit
      #do nothing - ignore.
    rescue Timeout::Error
      @resp.status = 408
      @hb.log_puts "The request timed out."
    end
  end

  def execute_done
    @cgroup.mark_done
    @cgroup.write_output
    @hb.log_puts "#{__id__} - Served '#{@meta["REQUEST_URI"]}' in #{Time.now.to_f - @time_start} secs (#{@resp.status})." if @debug
    @time_start = nil
    @cgroup.join
    @hb.events.call(:request_done, :httpsession => self) if @hb.events
    @httpsession_var = {}
  end
end
