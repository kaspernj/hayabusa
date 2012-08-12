class Hayabusa
  def initialize_cleaner
    #This should not be runned via _kas.timeout because timeout wont run when @should_restart is true! - knj
    Thread.new(&self.method(:clean_autorestart))
    
    #This flushes (writes) all session-data to the server and deletes old unused sessions from the database.
    self.timeout(:time => @config[:cleaner_timeout], &self.method(:clean_sessions))
  end
  
  def clean
    self.clean_sessions
    self.clean_autorestart
  end
  
  def clean_autorestart
    begin
      if @config[:autorestart]
        time = 1
      else
        time = 15
      end
      
      loop do
        sleep time
        
        if @config.has_key?(:restart_when_used_memory) and !@should_restart
          mbs_used = (Php4r.memory_get_usage / 1024) / 1024
          STDOUT.print "Restart when over #{@config[:restart_when_used_memory]}mb\n" if @config[:debug]
          STDOUT.print "Used: #{mbs_used}mb\n" if @config[:debug]
          
          if mbs_used.to_i >= @config[:restart_when_used_memory].to_i
            STDOUT.print "Memory is over #{@config[:restart_when_used_memory]} - restarting.\n"
            @should_restart = true
          end
        end
        
        if @should_restart and !@should_restart_done and !@should_restart_runnning
          begin
            @should_restart_runnning = true
            
            #When we begin to restart it should go as fast as possible - so start by flushing out any emails waiting so it goes faster the last time...
            STDOUT.print "Flushing mails.\n"
            self.mail_flush
            
            #Lets try to find a time where no thread is working within the next 30 seconds. If we cant - we interrupt after 10 seconds and restart the server.
            begin
              Timeout.timeout(30) do
                loop do
                  working_count = self.httpserv.working_count
                  working = false
                  
                  if working_count and working_count > 0
                    working = true
                    STDOUT.print "Someone is working - wait two sec and try to restart again!\n"
                  end
                  
                  if !working
                    STDOUT.print "Found window where no sessions were active - restarting!\n"
                    break
                  else
                    sleep 0.2
                  end
                  
                  STDOUT.print "Trying to find window with no active sessions to restart...\n"
                end
              end
            rescue Timeout::Error
              STDOUT.print "Could not find a timing window for restarting... Forcing restart!\n"
            end
            
            #Flush emails again if any are pending (while we tried to find a window to restart)...
            STDOUT.print "Flushing mails.\n"
            self.mail_flush
            
            STDOUT.print "Stopping appserver.\n"
            self.stop
            
            STDOUT.print "Figuring out restart-command.\n"
            mycmd = @config[:restart_cmd]
            
            if !mycmd or mycmd.to_s.strip.length <= 0
              fpath = File.realpath("#{File.dirname(__FILE__)}/../hayabusa.rb")
              mycmd = Knj::Os.executed_cmd
              
              STDOUT.print "Previous cmd: #{mycmd}\n"
              mycmd = mycmd.gsub(/\s+hayabusa.rb/, " #{Knj::Strings.unixsafe(fpath)}")
            end
            
            STDOUT.print "Restarting knjAppServer with command: #{mycmd}\n"
            @should_restart_done = true
            print exec(mycmd)
            exit
          rescue => e
            STDOUT.puts e.inspect
            STDOUT.puts e.backtrace
          end
        end
      end
    rescue => e
      self.handle_error(e)
    end
  end
  
  #This method can be used to clean the appserver. Dont call this from a HTTP-request.
  def clean_sessions
    STDOUT.print "Cleaning sessions on appserver.\n" if @config[:debug]
    
    #Clean up various inactive sessions.
    session_not_ids = []
    time_check = Time.now.to_i - 300
    newsessions = {}
    @sessions.each do |session_hash, session_data|
      session_data[:dbobj].flush
      
      if session_data[:time_lastused].to_i > time_check
        newsessions[session_hash] = session_data
        session_not_ids << session_data[:dbobj].id
      end
    end
    
    @sessions = newsessions
    
    STDOUT.print "Delete sessions...\n" if @config[:debug]
    @ob.list(:Session, {"id_not" => session_not_ids, "date_lastused_below" => (Time.now - 5356800)}) do |session|
      idhash = session[:idhash]
      STDOUT.print "Deleting session: '#{session.id}'.\n" if @config[:debug]
      @ob.delete(session)
      @sessions.delete(idhash)
    end
    
    #Clean database weak references from the tables-module.
    @db.clean
    
    #Clean the object-handler.
    @ob.clean_all
    
    #Call various user-connected methods.
    @events.call(:on_clean) if @events
  end
end