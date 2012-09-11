class Hayabusa::Cgi_tools
  attr_accessor :cgi
  
  #Converts CGI-like-post hashes to the normal Hayabusa-type hash.
  def convert_fcgi_post(params)
    post_hash = {}
    
    params.each do |key, val|
      post_hash[key] = val.first
    end
    
    post_ret = {}
    post_hash.each do |varname, value|
      Knj::Web.parse_name(post_ret, varname, value)
    end
    
    return post_ret
  end
  
  def env_table
    return ENV
  end
  
  def request_method
    return ENV["REQUEST_METHOD"]
  end
  
  def content_type
    return ENV["CONTENT_TYPE"]
  end
  
  def params
    return self.cgi.params
  end
  
  def print(arg)
    Kernel.print arg.to_s
  end
  
  #This method is used to proxy a request to another FCGI-process, since a single FCGI-process cant handle more requests simultanious.
  def proxy_request_to(args)
    cgi, http, fp_log = args[:cgi], args[:http], args[:fp_log]
    
    headers = {"Hayabusa_mode" => "proxy"}
    cgi.env_table.each do |key, val|
      if key[0, 5] == "HTTP_" and key != "HTTP_HAYABUSA_CGI_CONFIG"
        key = key[5, key.length].gsub("_", " ")
        key = key.to_s.split(" ").select{|w| w.capitalize! or w }.join(" ")
        key = key.gsub(" ", "-")
        headers[key] = val
      end
    end
    
    #Make request.
    uri = Knj::Web.parse_uri(cgi.env_table["REQUEST_URI"])
    url = File.basename(uri[:path])
    url = url[1, url.length] if url[0] == "/"
    
    if cgi.env_table["QUERY_STRING"].to_s.length > 0
      url << "?#{cgi.env_table["QUERY_STRING"]}"
    end
    
    #cgi.print "Content-Type: text/html\r\n"
    #cgi.print "\r\n"
    
    if args[:timeout]
      ttime = args[:timeout]
    else
      ttime = 30
    end
    
    fp_log.puts("Proxying URL: '#{url}'.") if fp_log
    
    require "timeout"
    Timeout.timeout(ttime) do
      if cgi.request_method == "POST" and cgi.content_type.to_s.downcase.index("multipart/form-data") != nil
        count = 0
        http.post_multipart(
          :url => url,
          :post => self.convert_fcgi_post(cgi.params),
          :default_headers => headers,
          :cookies => false,
          :on_content => proc{|line|
            cgi.print(line) if count > 0
            count += 1
          }
        )
      elsif cgi.request_method == "POST"
        count = 0
        http.post(
          :url => url,
          :post => self.convert_fcgi_post(cgi.params),
          :default_headers => headers,
          :cookies => false,
          :on_content => proc{|line|
            cgi.print(line) if count > 0
            count += 1
          }
        )
      else
        count = 0
        http.get(
          :url => url,
          :default_headers => headers,
          :cookies => false,
          :on_content => proc{|line|
            cgi.print(line) if count > 0
            count += 1
          }
        )
      end
    end
  end
end