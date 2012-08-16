class Hayabusa::Cgi_tools
  attr_accessor :cgi
  
  def convert_fcgi_post(params)
    post_hash = {}
    
    params.each do |key, val|
      post_hash[key] = val.first
    end
    
    post_ret = {}
    post_hash.each do |varname, value|
      Knj::Web.parse_name(post_ret, varname, value, :urldecode => true)
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
end