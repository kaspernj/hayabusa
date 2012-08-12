class Hayabusa
  def initialize_cmdline
    @cmds = {}
    
    Thread.new do
      begin
        $stdin.each_line do |line|
          called = 0
          @cmds.each do |key, connects|
            data = {}
            
            if key.is_a?(Regexp)
              if line.match(key)
                connects.each do |conn|
                  called += 1
                  conn[:block].call(data)
                end
              end
            else
              raise "Unknown class for 'cmd_connect': '#{key.class.name}'."
            end
          end
          
          if called == 0
            print "Unknown command: '#{line.strip}'.\n"
          end
        end
      rescue => e
        self.handle_error(e)
      end
    end
    
    self.cmd_connect(/^\s*restart\s*$/i, &self.method(:cmdline_on_restart_cmd))
    self.cmd_connect(/^\s*stop\s*$/i, &self.method(:cmdline_on_stop_cmd))
  end
  
  def cmdline_on_restart_cmd(data)
    print "Restart will begin shortly.\n"
    self.should_restart = true
  end
  
  def cmdline_on_stop_cmd(data)
    print "Stopping appserver.\n"
    self.stop
  end
  
  #Connects a proc to a specific command in the command-line (key should be a regex).
  def cmd_connect(cmd, &block)
    @cmds[cmd] = [] if !@cmds.key?(cmd)
    @cmds[cmd] << {:block => block}
  end
end