class Hayabusa::Erb_handler
  def initialize
    @connected = {}
  end
  
  def erb_handler(httpsess)
    eruby = httpsess.eruby
    
    if !@connected.key?(eruby.__id__)
      eruby.connect("error", &self.method(:on_error))
      @connected[eruby.__id__] = true
    end
    
    if !File.exists?(httpsess.page_path)
      eruby.import("#{File.dirname(__FILE__)}/../pages/error_notfound.rhtml")
    else
      eruby.import(httpsess.page_path)
    end
    
    httpsess.resp.status = 500 if eruby.error
  end
  
  #Handels the event when an error in the eruby-instance occurs.
  def on_error(e)
    _kas.handle_error(e)
  end
end