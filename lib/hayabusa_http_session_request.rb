require "knj/web"

#If we are running on JRuby or Rubinius this will seriously speed things up if we are behind a proxy.
if RUBY_PLATFORM == "java" or RUBY_ENGINE == "rbx"
  BasicSocket.do_not_reverse_lookup = true
end

#This class parses the various HTTP requests into easy programmable objects. Get, post, cookie, meta and so on...
class Hayabusa::Http_session::Request
  attr_reader :get, :post, :cookie, :meta, :page_path, :headers, :http_version, :read, :clength, :speed, :percent, :secs_left
  
  #Sets the various required data on the object. Hayabusa, crlf and arguments.
  def initialize(args)
    @args = args
    @hb = @args[:hb]
    @crlf = "\r\n"
  end
  
  #Reads content from the socket until the end of headers. Also does various error-checks.
  def read_socket(socket, cont)
    loop do
      if socket.closed?
        if !cont.empty?
          #This might just be the last allowed request...
          break
        else
          #This should not have happened...
          raise Errno::ECONNRESET, "Socket closed before trying to read."
        end
      end
      
      read = socket.gets
      raise Errno::ECONNRESET, "Socket returned non-string: '#{read.class.name}'." if !read.is_a?(String)
      cont << read
      break if cont[-4..-1] == "\r\n\r\n" or cont[-2..-1] == "\n\n"
    end
  end
  
  def reset
    @modified_since = nil
    @get = nil
    @post = nil
    @cookie = nil
    @meta = nil
    @page_path = nil
    @headers = nil
    @http_version = nil
    @read = nil
    @clength = nil
    @speec = nil
    @percent = nil
    @secs_left = nil
  end
  
  #Generates data on object from the given socket.
  def socket_parse(socket)
    self.reset
    cont = ""
    self.read_socket(socket, cont)
    
    #Parse URI (page_path and get).
    match = cont.match(/^(GET|POST|HEAD)\s+(.+)\s+HTTP\/1\.(\d+)\s*/)
    raise "Could not parse request: '#{cont.split("\n").first}'." if !match
    
    @http_version = "1.#{match[3]}"
    
    method = match[1]
    cont = cont.gsub(match[0], "")
    
    uri_raw = match[2]
    uri_raw = "index.rhtml" if uri_raw == ""
    
    uri = Knj::Web.parse_uri(match[2]) rescue {:path => match[2], :query => ""}
    
    page_filepath = Knj::Web.urldec(uri[:path])
    if page_filepath.empty? or page_filepath == "/" or File.directory?("#{@hb.config[:doc_root]}/#{page_filepath}")
      page_filepath = "#{page_filepath}/#{@hb.config[:default_page]}"
    end
    
    @page_path = "#{@hb.config[:doc_root]}/#{page_filepath}"
    @get = Knj::Web.parse_urlquery(uri[:query], :urldecode => true, :force_utf8 => true)
    
    if @get["_hb_httpsession_id"]
      @hb.httpsessions_ids[@get["_hb_httpsession_id"]] = @args[:httpsession]
    end
    
    begin
      #Parse headers, cookies and meta.
      @headers = {}
      @cookie = {}
      @meta = {
        "REQUEST_METHOD" => method,
        "QUERY_STRING" => uri[:query],
        "REQUEST_URI" => match[2],
        "SCRIPT_NAME" => uri[:path]
      }
      
      cont.scan(/^(\S+):\s*(.+)\r\n/) do |header_match|
        key = header_match[0].downcase
        val = header_match[1]
        
        @headers[key] = [] if !@headers.has_key?(key)
        @headers[key] << val
        
        case key
          when "cookie"
            Knj::Web.parse_cookies(val).each do |key, val|
              @cookie[key] = val
            end
          when "content-length"
            @clength = val.to_i
          else
            key = key.upcase.gsub("-", "_")
            @meta["HTTP_#{key}"] = val
        end
      end
      
      
      #Parse post
      @post = {}
      
      if method == "POST"
        post_treated = {}
        
        @speed = nil
        @read = 0
        post_data = ""
        
        Thread.new do
          begin
            time_cur = Time.now
            read_last = 0
            sleep 0.1
            
            while @clength and @read != nil and @read < @clength
              break if !@clength or !@read
              
              time_now = Time.now
              time_betw = time_now.to_f - time_cur.to_f
              read_betw = @read - read_last
              
              time_cur = time_now
              read_last = @read
              
              @percent = @read.to_f / @clength.to_f
              @speed = read_betw.to_f / time_betw.to_f
              
              bytes_left = @clength - read
              
              if @speed > 0 and bytes_left > 0
                @secs_left = bytes_left.to_f / @speed
              else
                @secs_left = false
              end
              
              sleep 2
            end
          rescue => e
            if @hb
              @hb.handle_error(e)
            else
              STDOUT.print Knj::Errors.error_str(e)
            end
          end
        end
        
        while @read < @clength
          read_size = @clength - @read
          read_size = 4096 if read_size > 4096
          
          raise Errno::ECONNRESET, "Socket closed." if socket.closed?
          read = socket.read(read_size)
          raise Errno::ECONNRESET, "Socket returned non-string: '#{read.class.name}'." if !read.is_a?(String)
          post_data << read
          @read += read.length
        end
        
        if @headers["content-type"] and match = @headers["content-type"].first.match(/^multipart\/form-data; boundary=(.+)\Z/)
          post_treated = Hayabusa::Http_session::Post_multipart.new(
            "io" => StringIO.new("#{post_data}"),
            "boundary" => match[1],
            "crlf" => @crlf
          ).return
          
          self.convert_post(@post, post_treated, {:urldecode => false})
        else
          post_data.split("&").each do |splitted|
            splitted = splitted.split("=")
            key = Knj::Web.urldec(splitted[0]).to_s.encode("utf-8")
            val = splitted[1].to_s.encode("utf-8")
            post_treated[key] = val
          end
          
          self.convert_post(@post, post_treated, {:urldecode => true})
        end
      end
    ensure
      @read = nil
      @speed = nil
      @clength = nil
      @percent = nil
      @secs_left = nil
      
      #If it doesnt get unset we could have a serious memory reference GC problem.
      if @get["_hb_httpsession_id"]
        @hb.httpsessions_ids.delete(@get["_hb_httpsession_id"])
      end
    end
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
  
  #Converts post-result to the right type of hash.
  def convert_post(seton, post_val, args = {})
    post_val.each do |varname, value|
      Knj::Web.parse_name(seton, varname, value, args)
    end
  end
end