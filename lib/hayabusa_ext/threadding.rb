class Hayabusa
  def initialize_threadding
    @config[:threadding] = {} if !@config.has_key?(:threadding)
    @config[:threadding][:max_running] = 16 if !@config[:threadding].has_key?(:max_running)
    
    threadpool_args = {:threads => @config[:threadding][:max_running]}
    threadpool_args[:priority] = @config[:threadding][:priority] if @config[:threadding].key?(:priority)
    
    @threadpool = Tpool.new(threadpool_args)
    @threadpool.on_error(&self.method(:threadpool_on_error))
  end
  
  #Callback for when an error occurs in the threadpool.
  def threadpool_on_error(args)
    self.handle_error(args[:error])
  end
  
  #Inits the thread so it has access to the appserver and various magic methods can be used.
  def thread_init(thread = Thread.current)
    thread[:hayabusa] = {} if !thread[:hayabusa]
    thread[:hayabusa][:hb] = self
    return nil
  end
  
  #Spawns a new thread with access to magic methods, _db-method and various other stuff in the appserver.
  def thread(args = {})
    raise "No block given." if !block_given?
    args[:args] = [] if !args[:args]
    
    thread_obj = Hayabusa::Thread_instance.new(
      :running => false,
      :error => false,
      :done => false,
      :args => args
    )
    
    @threadpool.run_async do
      begin
        @ob.db.get_and_register_thread if @ob.db.opts[:threadsafe]
        @db_handler.get_and_register_thread if @db_handler.opts[:threadsafe]
        
        Thread.current[:hayabusa] = {
          :hb => self,
          :db => @db_handler
        }
        
        thread_obj.args[:running] = true
        yield(*args[:args])
      rescue => e
        thread_obj.args[:error] = true
        thread_obj.args[:error_obj] = e
        
        self.handle_error(e)
      ensure
        thread_obj.args[:running] = false
        thread_obj.args[:done] = true
        @ob.db.free_thread if @ob.db.opts[:threadsafe]
        @db_handler.free_thread if @db_handler.opts[:threadsafe]
      end
    end
    
    return thread_obj
  end
  
  #If a custom thread is spawned, you can run whatever code within this block, and it will have its own database-connection and so on like normal Hayabusa-threads.
  def thread_block(&block)
    @ob.db.get_and_register_thread if @ob.db.opts[:threadsafe]
    @db_handler.get_and_register_thread if @db_handler.opts[:threadsafe]
    
    thread = Thread.current
    thread[:hayabusa] = {} if !thread[:hayabusa]
    thread[:hayabusa][:hb] = self
    
    begin
      return block.call
    ensure
      @ob.db.free_thread if @ob.db.opts[:threadsafe]
      @db_handler.free_thread if @db_handler.opts[:threadsafe]
    end
  end
  
  #Runs a proc every number of seconds.
  def timeout(args = {}, &block)
    return Hayabusa::Threadding_timeout.new({
      :hb => self,
      :block => block,
      :args => []
    }.merge(args)).start
  end
  
  #Spawns a thread to run the given proc and add the output of that block in the correct order to the HTML.
  def threadded_content(&block)
    _httpsession.threadded_content(block)
    return nil
  end
end

class Hayabusa::Thread_instance
  attr_reader :args
  
  def initialize(args)
    @args = args
  end
  
  def running?
    return @args[:running]
  end
  
  def done?
    return @args[:done]
  end
  
  def error?
    return true if @args[:error]
    return false
  end
  
  def join
    while !@args[:done] and !@args[:error]
      sleep 0.1
    end
  end
  
  def join_error
    self.join
    raise @args[:error_obj] if @args[:error_obj]
  end
end