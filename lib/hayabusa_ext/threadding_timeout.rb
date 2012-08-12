class Hayabusa::Threadding_timeout
  attr_reader :timeout
  
  def initialize(args)
    @args = args
    @kas = @args[:kas]
    raise "No time given." if !@args.key?(:time)
    @mutex = Mutex.new
    @running = false
  end
  
  def time=(newtime)
    @args[:time] = newtime.to_s.to_i
  end
  
  def time
    return @args[:time]
  end
  
  #Starts the timeout.
  def start
    @run = true
    @thread = Thread.new do
      loop do
        begin
          if @args[:counting]
            @timeout = @args[:time]
            
            while @timeout > 0
              @timeout += -1
              break if @kas.should_restart or !@run
              sleep 1
            end
          else
            sleep @args[:time]
          end
          
          break if @kas.should_restart or !@run
          
          @mutex.synchronize do
            @kas.threadpool.run do
              @kas.ob.db.get_and_register_thread if @kas.ob.db.opts[:threadsafe]
              @kas.db_handler.get_and_register_thread if @kas.db_handler.opts[:threadsafe]
              
              Thread.current[:hayabusa] = {
                :kas => @kas,
                :db => @kas.db_handler
              }
              
              begin
                @running = true
                
                if @args.key?(:timeout)
                  Timeout.timeout(@args[:timeout]) do
                    @args[:block].call(*@args[:args])
                  end
                else
                  @args[:block].call(*@args[:args])
                end
              ensure
                @running = false
                @kas.ob.db.free_thread if @kas.ob.db.opts[:threadsafe]
                @kas.db_handler.free_thread if @kas.db_handler.opts[:threadsafe]
              end
            end
          end
        rescue => e
          @kas.handle_error(e)
        end
      end
    end
    
    return self
  end
  
  #Stops the timeout.
  def stop
    @run = false
    @mutex.synchronize do
      @thread.kill if @thread.alive?
      @thread = nil
    end
  end
  
  #Returns various data.
  def [](key)
    return @timeout if key == :hayabusa_timeout
    raise "No such key: '#{key}'."
  end
  
  #Returns true if the thread is alive or not.
  def alive?
    return @thread.alive? if @thread
    return false
  end
  
  #Returns true if the timeout is running or not.
  def running?
    return @running
  end
end