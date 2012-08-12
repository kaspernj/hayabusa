#encoding: utf-8

#This class handels the adding of content and writing to socket. Since this can be done with multiple threads and multiple IO's it can get complicated.
class Hayabusa::Http_session::Contentgroup
  attr_reader :done, :cur_data
  attr_accessor :chunked, :socket
  NL = "\r\n"
  
  def initialize(args = {})
    @socket = args[:socket]
    @chunked = args[:chunked]
    @resp = args[:resp]
    @httpsession = args[:httpsession]
    @mutex = Mutex.new
    @debug = false
  end
  
  def init
    @done = false
    @thread = nil
    @cur_data = {
      :str => "",
      :done => false
    }
    @ios = [@cur_data]
  end
  
  def reset
    @ios = []
    @done = false
    @thread = nil
    @forced = false
    
    @mutex.synchronize do
      self.new_io
    end
    
    self.register_thread
  end
  
  def new_io(obj = "")
    @cur_data[:done] = true if @cur_data
    @cur_data = {:str => obj, :done => false}
    @ios << @cur_data
  end
  
  #Forces the content to be the input - nothing else can be added after calling this.
  def force_content(newcont)
    @ios = [{:str => newcont, :done => true}]
  end
  
  def register_thread
    Thread.current[:hayabusa] = {} if !Thread.current[:hayabusa]
    Thread.current[:hayabusa][:contentgroup] = self
  end
  
  def new_thread
    cgroup = Hayabusa::Http_session::Contentgroup.new(:socket => @socket, :chunked => @chunked)
    cgroup.init
    
    @mutex.synchronize do
      @ios << cgroup
      self.new_io
    end
    
    self.register_thread
    return cgroup
  end
  
  def write_begin
    begin
      @resp.write if @httpsession.meta["METHOD"] != "HEAD"
    rescue Errno::ECONNRESET, Errno::ENOTCONN, Errno::EPIPE
      #Ignore - the user probaly left.
    end
  end
  
  def write(cont)
    @mutex.synchronize do
      @cur_data[:str] << cont
    end
  end
  
  def write_output
    return nil if @thread
    
    @mutex.synchronize do
      @thread = Thread.new do
        begin
          self.write_begin
        rescue => e
          STDERR.puts "Error while writing."
          STDERR.puts e.inspect
          STDERR.puts e.backtrace
        end
      end
    end
  end
  
  def write_force
    @mutex.synchronize do
      @forced = true if !@thread
    end
    
    if @thread
      @thread.join
    else
      self.write_begin
    end
  end
  
  def mark_done
    @cur_data[:done] = true
    @done = true
  end
  
  def join
    return nil if @forced
    sleep 0.1 while !@thread
    @thread.join
  end
  
  def write_to_socket
    count = 0
    
    @ios.each do |data|
      if data.is_a?(Hayabusa::Http_session::Contentgroup)
        data.write_to_socket
      elsif data.key?(:str)
        if data[:str].is_a?(Hash) and data[:str][:type] == :file
          File.open(data[:str][:path], "r") do |file|
            loop do
              begin
                buf = file.sysread(16384)
              rescue EOFError
                break
              end
              
              if @chunked
                @socket.write("#{buf.length.to_s(16)}#{NL}#{buf}#{NL}")
              else
                @socket.write(buf)
              end
            end
          end
        else
          loop do
            break if data[:done] and data[:str].size <= 0 
            sleep 0.1 while data[:str].size < 512 and !data[:done]
            
            str = nil
            @mutex.synchronize do
              str = data[:str].bytes
              data[:str] = ""
            end
            
            #512 could take a long time for big pages. 16384 seems to be an optimal number.
            str.each_slice(16384) do |slice|
              buf = slice.pack("C*")
              
              if @chunked
                @socket.write("#{buf.length.to_s(16)}#{NL}#{buf}#{NL}")
              else
                @socket.write(buf)
              end
            end
          end
        end
      else
        raise "Unknown object: '#{data.class.name}'."
      end
    end
    
    count += 1
  end
end