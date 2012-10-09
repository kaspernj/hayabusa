require "tempfile"

class Hayabusa::Cgi_tools
  attr_accessor :cgi
  
  #Converts CGI-like-post hashes to the normal Hayabusa-type hash.
  def convert_fcgi_post(params, args = nil)
    post_hash = {}
    
    params.each do |key, realval|
      val = realval.first
      classn = val.class.name
      
      #Sometimes uploaded files are given as StringIO's.
      if classn == "StringIO" or classn == "Tempfile"
        val = Hayabusa::Http_session::Post_multipart::File_upload.new(
          :fname => val.original_filename,
          :data => val
        )
      end
      
      post_hash[key] = val
    end
    
    post_ret = {}
    post_hash.each do |varname, value|
      Knj::Web.parse_name(post_ret, varname, value)
    end
    
    return post_ret
  end
  
  #Converts the post-hash to valid hash for Http2 regarding file uploads (when proxied to host-process via Http2-framework).
  def convert_fcgi_post_fileuploads_to_http2(hash)
    hash.each do |key, val|
      if val.is_a?(Hayabusa::Http_session::Post_multipart::File_upload)
        hash[key] = {
          :filename => val.filename,
          :content => val.to_s
        }
      elsif val.is_a?(Hash) or val.is_a?(Array)
        hash[key] = self.convert_fcgi_post_fileuploads_to_http2(val)
      end
    end
    
    return hash
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
      keyl = key.to_s.downcase
      
      if key[0, 5] == "HTTP_"
        key = key[5, key.length].gsub("_", " ")
        key = key.to_s.split(" ").select{|w| w.capitalize! or w }.join(" ")
        key = key.gsub(" ", "-")
        keyl = key.downcase
        
        if keyl != "connection" and keyl != "accept-encoding" and keyl != "hayabusa-fcgi-config" and key != "hayabusa-cgi-config"
          headers[key] = val
        end
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
    
    #The HTTP-connection can have closed mean while, so we have to test it.
    raise Errno::ECONNABORTED if !http.socket_working?
    
    #require "timeout"
    #Timeout.timeout(ttime) do
      if cgi.request_method == "POST" and cgi.content_type.to_s.downcase.index("multipart/form-data") != nil
        count = 0
        http.post_multipart(
          :url => url,
          :post => self.convert_fcgi_post_fileuploads_to_http2(self.convert_fcgi_post(cgi.params, :http2_compatible => true)),
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
          :post => self.convert_fcgi_post(cgi.params, :http2_compatible => true),
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
    #end
  end
end