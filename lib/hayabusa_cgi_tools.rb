class Hayabusa::Cgi_tools
  def convert_fcgi_post(params)
    post_hash = {}
    
    params.each do |key, val|
      post_hash[key] = val.first
    end
    
    post_ret = {}
    self.convert_post(post_ret, post_hash, {:urldecode => true})
    
    return post_ret
  end
  
  #Converts post-result to the right type of hash.
  def convert_post(seton, post_val, args = {})
    post_val.each do |varname, value|
      Knj::Web.parse_name(seton, varname, value, args)
    end
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
  
  def cgi
    require "cgi"
    @cgi = CGI.new if !@cgi
    return @cgi
  end
  
  def params
    return self.cgi.params
  end
  
  def print(arg)
    Kernel.print arg.to_s
  end
end