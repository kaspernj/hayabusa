class Hayabusa
  #Imports a .rhtml-file and executes it.
  #===Examples
  #  _hb.import("/some/path/page.rhtml")
  def import(filepath)
    if filepath.to_s.index("../proc/self") != nil
      raise Errno::EACCES, "Possible attempt to hack the appserver."
    end
    
    _httpsession.eruby.import(filepath)
  end
  
  #Redirects to another URL.
  #===Examples
  #  _hb.redirect("someotherpage.rhtml")
  #  _hb.redirect("newpage.rhtml", :perm => true)
  def redirect(url, args = {})
    #Header way
    if !_httpsession.alert_sent and !self.headers_sent?
      if args[:perm]
        _httpsession.resp.status = 301 if !self.headers_sent?
      else
        _httpsession.resp.status = 303 if !self.headers_sent?
      end
      
      self.header("Location", url) if !self.headers_sent?
    end
    
    print "<script type=\"text/javascript\">location.href=\"#{url}\";</script>"
    exit
  end
  
  #Sends a javascript-alert to the HTML.
  #===Examples
  #  _hb.alert("Hello world!")
  def alert(msg)
    _httpsession.alert_sent = true
    Knj::Web.alert(msg)
    return self
  end
  
  #Define a cookies in the clients browser.
  #===Examples
  #  _hb.cookie(:name => "MyCookie", :value => "Trala")
  def cookie(cookie)
    raise "No HTTP-session attached to this thread." if !_httpsession
    raise "HTTP-session not active." if !_httpsession.resp
    raise "Not a hash: '#{cookie.class.name}', '#{cookie}'." unless cookie.is_a?(Hash)
    _httpsession.resp.cookie(cookie)
    return nil
  end
  
  #Sends a header to the clients browser.
  #===Examples
  #  _hb.header("Content-Type", "text/javascript")
  def header(key, val)
    raise "No HTTP-session attached to this thread." if !_httpsession
    raise "HTTP-session not active." if !_httpsession.resp
    _httpsession.resp.header(key, val)
    return nil
  end
  
  #Sends a raw header-line to the clients browser.
  def header_raw(str)
    raise "No HTTP-session attached to this thread." if !_httpsession
    raise "HTTP-session not active." if !_httpsession.resp
    Php4r.header(str)
    return nil
  end
  
  #Returns true if the headers are already sent.
  #===Examples
  #  _hb.headers_sent? #=> true
  def headers_sent?
    return true if _httpsession.resp.headers_sent
    return false
  end
  
  #Define the size for when to automatically send headers. If you want to send hundres of kilobytes and then a header, you can use this method to do so.
  #===Examples
  #Set the size to 200 kb.
  #  _hb.headers_send_size = (1024 * 200)
  def headers_send_size=(newsize)
    raise "The headers are already sent and you cannot modify the send-size any more." if self.headers_sent?
    _httpsession.size_send = newsize.to_i
    return nil
  end
  
  #Serves the given filepath and enables caching for it. No other content should be written to the page when using this method.
  #===Examples
  #  _hb.header("Content-Type", "text/javascript")
  #  _hb.serve_file("somefile.js")
  def serve_file(filepath)
    raise "File doesnt exist: '#{filepath}'." if !File.exists?(filepath)
    httpsess = _httpsession
    headers = httpsess.headers
    resp = httpsess.resp
    
    if headers["cache-control"] and headers["cache-control"][0]
      cache_control = {}
      headers["cache-control"][0].scan(/(.+)=(.+)/) do |match|
        cache_control[match[1]] = match[2]
      end
    end
    
    cache_dont = true if cache_control and cache_control.key?("max-age") and cache_control["max-age"].to_i <= 0
    lastmod = File.mtime(filepath)
    
    self.header("Last-Modified", lastmod.httpdate)
    self.header("Expires", (Time.now + 86400).httpdate) #next day.
    
    if !cache_dont and headers["if-modified-since"] and headers["if-modified-since"][0]
      request_mod = Datet.in(headers["if-modified-since"].first).time
      
      if request_mod == lastmod
        resp.status = 304
        return nil
      end
    end
    
    httpsess.force_content(:type => :file, :path => filepath)
    return nil
  end
  
  #Sends a javascript back to the browser and exits.
  def back
    Knj::Web.back
  end
  
  #Draw a input in a table.
  def inputs(*args)
    return Knj::Web.inputs(args)
  end
  
  #Urlencodes a string.
  #===Examples
  #  _hb.redirect("mypage.rhtml?arg=#{_hb.urlenc(value_variable)}")
  def urlenc(str)
    return Knj::Web.urlenc(str)
  end
  
  #Urldecodes a string.
  def urldec(str)
    return Knj::Web.urldec(str)
  end
  
  #Returns a number localized as a string.
  def num(*args)
    return Knj::Locales.number_out(*args)
  end
  
  #Hashes with numeric keys will be turned into arrays instead. This is not done automatically because it can wrongly corrupt data if not used correctly.
  def get_parse_arrays(arg = nil, ob = nil)
    arg = _get.clone if !arg
    
    #Parses key-numeric-hashes into arrays and converts special model-strings into actual models.
    if arg.is_a?(Hash) and Knj::ArrayExt.hash_numeric_keys?(arg)
      arr = []
      
      arg.each do |key, val|
        arr << val
      end
      
      return self.get_parse_arrays(arr, ob)
    elsif arg.is_a?(Hash)
      arg.each do |key, val|
        arg[key] = self.get_parse_arrays(val, ob)
      end
      
      return arg
    elsif arg.is_a?(Array)
      arg.each_index do |key|
        arg[key] = self.get_parse_arrays(arg[key], ob)
      end
      
      return arg
    elsif arg.is_a?(String) and match = arg.match(/^#<Model::(.+?)::(\d+)>$/)
      ob = @ob if !ob
      return ob.get(match[1], match[2])
    else
      return arg
    end
  end
  
  #Returns the socket-port the appserver is currently running on.
  def port
    raise "Http-server not spawned yet. Call Hayabusa#start to spawn it." if !@httpserv
    return @httpserv.server.addr[1]
  end
end