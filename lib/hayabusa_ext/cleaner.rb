class Hayabusa
  def initialize_cleaner
    #This should not be runned via _hb.timeout because timeout wont run when @should_restart is true! - knj
    Thread.new(&self.method(:clean_autorestart))

    #This flushes (writes) all session-data to the server and deletes old unused sessions from the database.
    self.timeout(:time => @config[:cleaner_timeout], &self.method(:clean_sessions))
  end

  def clean
    self.clean_sessions
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
          self.log_puts("Restart when over #{@config[:restart_when_used_memory]}mb") if @debug
          self.log_puts("Used: #{mbs_used}mb") if @debug

          if mbs_used.to_i >= @config[:restart_when_used_memory].to_i
            self.log_puts("Memory is over #{@config[:restart_when_used_memory]} - restarting.") if @debug
            @should_restart = true
          end
        end

        if @should_restart and !@should_restart_done and !@should_restart_runnning
          begin
            @should_restart_runnning = true

            #When we begin to restart it should go as fast as possible - so start by flushing out any emails waiting so it goes faster the last time...
            self.log_puts("Flushing mails.") if @debug
            self.mail_flush

            #Lets try to find a time where no thread is working within the next 30 seconds. If we cant - we interrupt after 10 seconds and restart the server.
            begin
              Timeout.timeout(30) do
                loop do
                  working_count = self.httpserv.working_count
                  working = false

                  if working_count and working_count > 0
                    working = true
                    self.log_puts("Someone is working - wait two sec and try to restart again!") if @debug
                  end

                  if !working
                    self.log_puts("Found window where no sessions were active - restarting!") if @debug
                    break
                  else
                    sleep 0.2
                  end

                  self.log_puts("Trying to find window with no active sessions to restart...") if @debug
                end
              end
            rescue Timeout::Error
              self.log_puts("Could not find a timing window for restarting... Forcing restart!") if @debug
            end

            #Flush emails again if any are pending (while we tried to find a window to restart)...
            self.log_puts("Flushing mails.") if @debug
            self.mail_flush

            self.log_puts("Stopping appserver.") if @debug
            self.stop

            self.log_puts("Figuring out restart-command.") if @debug
            mycmd = @config[:restart_cmd]

            if !mycmd or mycmd.to_s.strip.length <= 0
              fpath = File.realpath("#{File.dirname(__FILE__)}/../hayabusa.rb")
              mycmd = Knj::Os.executed_cmd

              self.log_puts("Previous cmd: #{mycmd}") if @debug
              mycmd = mycmd.gsub(/\s+hayabusa.rb/, " #{Knj::Strings.unixsafe(fpath)}")
            end

            self.log_puts("Restarting knjAppServer with command: #{mycmd}") if @debug
            @should_restart_done = true
            print exec(mycmd)
            exit
          rescue => e
            self.log_puts(e.inspect)
            self.log_puts(e.backtrace)
          end
        end
      end
    rescue => e
      self.handle_error(e)
    end
  end

  #This method can be used to clean the appserver. Dont call this from a HTTP-request.
  def clean_sessions
    self.log_puts("Cleaning sessions on appserver.") if @debug

    #Clean up various inactive sessions.
    session_not_ids = []
    time_check = Time.now.to_i - 300
    @sessions.delete_if do |session_hash, session_data|
      session_data[:dbobj].flush

      if session_data[:dbobj].date_lastused.to_i > time_check
        session_not_ids << session_data[:dbobj].id
        false
      else
        true
      end
    end

    self.log_puts("Delete sessions...") if @debug
    @ob.list(:Session, {"id_not" => session_not_ids, "date_lastused_below" => (Time.now - 5356800)}) do |session|
      idhash = session[:idhash]
      self.log_puts("Deleting session: '#{session.id}'.") if @debug
      @ob.delete(session)
      @sessions.delete(idhash)
    end

    #Clean database weak references from the tables-module.
    @db.clean if @db.respond_to?(:clean)

    #Clean the object-handler.
    @ob.clean_all

    #Call various user-connected methods.
    @events.call(:on_clean) if @events
  end
end