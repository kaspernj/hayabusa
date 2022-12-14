require "cgi"

class CGI
  public :env_table
  def self.remove_params
    if (const_defined?(:CGI_PARAMS))
      remove_const(:CGI_PARAMS)
      remove_const(:CGI_COOKIES)
    end
  end
end

# A hack to use CGI in FCGI mode (copied from the original FCGI framework).
class Hayabusa::Cgi < CGI
  def initialize(request, *args)
    ::CGI.remove_params
    @request = request
    super(*args)
    @args = *args
  end
  
  def args
    @args
  end
  
  def env_table
    @request.env
  end
  
  def stdinput
    @request.in
  end
  
  def stdoutput
    @request.out
  end
end