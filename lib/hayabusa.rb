require "base64"
require "digest"
require "stringio"
require "timeout"

#The class that stands for the whole appserver / webserver.
#===Examples
# appsrv = Hayabusa.new(
#   :locales_root => "/some/path/locales",
#   :locales_gettext_funcs => true,
#   :magic_methods => true
# )
# appsrv.start
# appsrv.join
class Hayabusa
  @@path = File.dirname(__FILE__)
  
  attr_reader :cio, :config, :httpserv, :debug, :db, :db_handler, :ob, :translations, :paused, :should_restart, :events, :mod_event, :db_handler, :gettext, :sessions, :logs_access_pending, :threadpool, :vars, :magic_procs, :magic_vars, :types, :eruby_cache, :httpsessions_ids
  attr_accessor :served, :should_restart, :should_restart_done
  
  #Autoloader for subclasses.
  def self.const_missing(name)
    require "#{File.dirname(__FILE__)}/hayabusa_#{name.to_s.downcase}.rb"
    return Hayabusa.const_get(name)
  end
  
  def initialize(config)
    raise "No arguments given." if !config.is_a?(Hash)
    
    @config = {
      :host => "0.0.0.0",
      :timeout => 30,
      :default_page => "index.rhtml",
      :default_filetype => "text/html",
      :max_requests_working => 20,
      :size_send => 1024,
      :cleaner_timeout => 300,
      :mailing_time => 30
    }.merge(config)
    
    @config[:smtp_args] = {"smtp_host" => "localhost", "smtp_port" => 25} if !@config[:smtp_args]
    @config[:timeout] = 30 if !@config.has_key?(:timeout)
    raise "No ':doc_root' was given in arguments." if !@config.has_key?(:doc_root)
    
    
    #Require gems.
    require "rubygems"
    gems = [
      [:Erubis, "erubis"],
      [:Knj, "knjrbfw"],
      [:Tsafe, "tsafe"],
      [:Tpool, "tpool"]
    ]
    
    gems.each do |gem|
      if Kernel.const_defined?(gem[0])
        puts "Gem already loaded: '#{gem[1]}'." if @debug
        next
      end
      
      fpath = "#{@@path}/../../#{gem[1]}/lib/#{gem[1]}.rb"
      
      if File.exists?(fpath)
        puts "Loading custom gem-path: '#{fpath}'." if @debug
        require fpath
      else
        puts "Loading gem: '#{gem[1]}'." if @debug
        require gem[1]
      end
    end
    
    
    #Setup default handlers if none are given.
    if !@config.has_key?(:handlers)
      @erb_handler = Hayabusa::Erb_handler.new
      @config[:handlers] = [
        {
          :file_ext => "rhtml",
          :callback => @erb_handler.method(:erb_handler)
        },{
          :path => "/fckeditor",
          :mount => "/usr/share/fckeditor"
        }
      ]
    end
    
    if @config[:handlers_extra]
      @config[:handlers] += @config[:handlers_extra]
    end
    
    
    #Add extra handlers if given.
    @config[:handlers] += @config[:handlers_extra] if @config[:handlers_extra]
    
    
    #Setup cache to make .rhtml-calls faster.
    @config[:handlers_cache] = {}
    @config[:handlers].each do |handler_info|
      next if !handler_info[:file_ext] or !handler_info[:callback]
      @config[:handlers_cache][handler_info[:file_ext]] = handler_info[:callback]
    end
    
    
    @debug = @config[:debug]
    if @debug
      if !@config.key?(:debug_log) or @config[:debug_log]
        @debug_log = true
      else
        @debug_log = false
      end
      
      if @config[:debug_print]
        @debug_print = true
      else
        @debug_print = false
      end
      
      if !@config.key?(:debug_print_err) or @config[:debug_print_err]
        @debug_print_err = true
      end
    end
    
    @paused = 0
    @paused_mutex = Mutex.new
    @should_restart = false
    @mod_events = {}
    @served = 0
    @mod_files = {}
    @sessions = {}
    @eruby_cache = {}
    @httpsessions_ids = {}
    
    if @debug_log
      @log_fp = File.open("/tmp/hayabusa_#{@config[:title]}.log", "w")
      @log_fp.sync = true
    end
    
    @path_hayabusa = File.dirname(__FILE__)
    
    
    #If auto-restarting is enabled - start the modified events-module.
    if @config[:autorestart]
      paths = [
        "#{@path_hayabusa}/class_customio.rb"
      ]
      
      self.log_puts "Auto restarting." if @debug
      @mod_event = Knj::Event_filemod.new(:wait => 2, :paths => paths, &self.method(:on_event_filemod))
    end
    
    
    #Set up default file-types and merge given filetypes into it.
    @types = {
      :ico => "image/x-icon",
      :jpeg => "image/jpeg",
      :jpg => "image/jpeg",
      :gif => "image/gif",
      :png => "image/png",
      :html => "text/html",
      :htm => "text/html",
      :rhtml => "text/html",
      :css => "text/css",
      :xml => "text/xml",
      :js => "text/javascript"
    }
    @types.merge!(@config[:filetypes]) if @config.key?(:filetypes)
    
    
    
    #Load various required files in the hayabusa-framework.
    files = [
      "#{@path_hayabusa}/hayabusa_ext/errors.rb",
      "#{@path_hayabusa}/hayabusa_ext/logging.rb",
      "#{@path_hayabusa}/hayabusa_ext/mailing.rb",
      "#{@path_hayabusa}/hayabusa_ext/sessions.rb",
      "#{@path_hayabusa}/hayabusa_ext/translations.rb",
      "#{@path_hayabusa}/hayabusa_ext/web.rb"
    ]
    
    files.each do |file|
      self.log_puts "Loading: '#{file}'." if @debug
      self.loadfile(file)
    end
    
    
    self.log_puts "Setting up database." if @debug
    if @config[:db].is_a?(Knj::Db)
      @db = @config[:db]
    elsif @config[:db].is_a?(Hash)
      @db = Knj::Db.new(@config[:db])
    elsif @config[:db_args]
      @db = Knj::Db.new(@config[:db_args])
    else
      if @config[:title]
        db_title = @config[:title]
      else
        db_title = Time.now.to_f.to_s.hash
      end
      
      db_path = "#{Knj::Os.tmpdir}/hayabusa_fallback_db_#{db_title}.sqlite3"
      @config[:dbrev] = true
      
      require "sqlite3" if RUBY_ENGINE != "jruby"
      @db = Knj::Db.new(
        :type => "sqlite3",
        :path => db_path,
        :return_keys => "symbols",
        :index_append_table_name => true
      )
    end
    
    
    if !@config.key?(:dbrev) or @config[:dbrev]
      self.log_puts "Updating database." if @debug
      dbrev_args = {"schema" => Hayabusa::Database::SCHEMA, "db" => @db}
      dbrev_args.merge!(@config[:dbrev_args]) if @config.key?(:dbrev_args)
      Knj::Db::Revision.new.init_db(dbrev_args)
      dbrev_args = nil
    end
    
    
    self.log_puts "Spawning objects." if @debug
    @ob = Knj::Objects.new(
      :db => db,
      :class_path => @path_hayabusa,
      :module => Hayabusa::Models,
      :datarow => true,
      :hayabusa => self,
      :require => false
    )
    @ob.events.connect(:no_date, &self.method(:no_date))
    
    
    if @config[:httpsession_db_args]
      @db_handler = Knj::Db.new(@config[:httpsession_db_args])
    else
      @db_handler = @db
    end
    
    
    if @config[:locales_root]
      @gettext = Knj::Gettext_threadded.new("dir" => config[:locales_root])
    end
    
    require "#{@path_hayabusa}/kernel_ext/gettext_methods" if @config[:locales_gettext_funcs]
    
    if @config[:magic_methods] or !@config.has_key?(:magic_methods)
      self.log_puts "Loading magic-methods." if @debug
      require "#{@path_hayabusa}/kernel_ext/magic_methods"
    end
    
    if @config[:customio] or !@config.has_key?(:customio)
      self.log_puts "Loading custom-io." if @debug
      
      if $stdout.class.name != "Hayabusa::Custom_io"
        @cio = Hayabusa::Custom_io.new
        $stdout = @cio
      end
    end
    
    
    #Save the PID to the run-file.
    self.log_puts "Setting run-file." if @debug
    tmpdir = "#{Knj::Os.tmpdir}/hayabusa"
    tmppath = "#{tmpdir}/run_#{@config[:title]}"
    
    if !File.exists?(tmpdir)
      Dir.mkdir(tmpdir)
      File.chmod(0777, tmpdir)
    end
    
    File.open(tmppath, "w") do |fp|
      fp.write(Process.pid)
    end
    File.chmod(0777, tmppath)
    
    
    #Set up various events for the appserver.
    if !@config.key?(:events) or @config[:events]
      self.log_puts "Loading events." if @debug
      @events = Knj::Event_handler.new
      @events.add_event(
        :name => :check_page_access,
        :connections_max => 1
      )
      @events.add_event(
        :name => :ob,
        :connections_max => 1
      )
      @events.add_event(
        :name => :trans_no_str,
        :connections_max => 1
      )
      @events.add_event(
        :name => :request_done,
        :connections_max => 1
      )
      @events.add_event(
        :name => :request_begin,
        :connections_max => 1
      )
      
      #This event is used if the user himself wants stuff to be cleaned up when the appserver is cleaning up stuff.
      @events.add_event(
        :name => :on_clean
      )
    end
    
    #Set up the 'vars'-variable that can be used to set custom global variables for web-requests.
    @vars = Knj::Hash_methods.new
    @magic_vars = {}
    @magic_procs = {}
    
    
    #Initialize the various feature-modules.
    self.log_puts "Init sessions." if @debug
    self.initialize_sessions
    
    if !@config.key?(:threadding) or @config[:threadding]
      self.loadfile("#{@path_hayabusa}/hayabusa_ext/threadding.rb")
      self.loadfile("#{@path_hayabusa}/hayabusa_ext/threadding_timeout.rb")
      self.log_puts "Init threadding." if @debug
      self.initialize_threadding
    end
    
    self.log_puts "Init mailing." if @debug
    self.initialize_mailing
    
    self.log_puts "Init errors." if @debug
    self.initialize_errors
    
    self.log_puts "Init logging." if @debug
    self.initialize_logging
    
    if !@config.key?(:cleaner) or @config[:cleaner]
      self.loadfile("#{@path_hayabusa}/hayabusa_ext/cleaner.rb")
      self.log_puts "Init cleaner." if @debug
      self.initialize_cleaner
    end
    
    if !@config.key?(:cmdline) or @config[:cmdline]
      self.loadfile("#{@path_hayabusa}/hayabusa_ext/cmdline.rb")
      self.log_puts "Init cmdline." if @debug
      self.initialize_cmdline
    end
    
    
    #Clear memory at exit.
    Kernel.at_exit(&self.method(:stop))
    
    
    self.log_puts "Appserver spawned." if @debug
  end
  
  #Outputs to stderr and logs it.
  def log_puts(str)
    if @debug_log
      @log_fp.sync = true
      @log_fp.puts str
    end
    
    if @debug_print
      STDOUT.sync = true
      STDOUT.puts str
    end
    
    if @debug_print_err
      STDERR.sync = true
      STDERR.puts str
    end
  end
  
  def no_date(event, classname)
    return "[no date]"
  end
  
  def on_event_filemod(event, path)
    self.log_puts "File changed - restart server: #{path}"
    @should_restart = true
    @mod_event.destroy if @mod_event
  end
  
  #If you want to use auto-restart, every file reloaded through loadfile will be watched for changes. When changed the server will do a restart to reflect that.
  def loadfile(fpath)
    if !@config[:autorestart]
      require fpath
      return nil
    end
    
    rpath = File.realpath(fpath)
    raise "No such filepath: #{fpath}" if !rpath or !File.exists?(rpath)
    
    return true if @mod_files[rpath]
    
    @mod_event.args[:paths] << rpath
    @mod_files = rpath
    
    require rpath
    return false
  end
  
  #Start a new CGI-request.
  def start_cgi_request
    @cgi_http_session = Hayabusa::Cgi_session.new(:hb => self)
  end
  
  #Starts the HTTP-server and threadpool.
  def start
    #Start the appserver.
    self.log_puts "Spawning appserver." if @debug
    @httpserv = Hayabusa::Http_server.new(self)
    @httpserv.start
    
    
    self.log_puts "Starting appserver." if @debug
    Thread.current[:hayabusa] = {:hb => self} if !Thread.current[:hayabusa]
    
    if @config[:autoload]
      self.log_puts "Autoloading #{@config[:autoload]}" if @debug
      require @config[:autoload]
    end
    
    self.log_puts "Appserver startet." if @debug
  end
  
  #Stops the entire app and releases join.
  def stop
    return nil if @stop_called
    @stop_called = true
    
    self.log_puts "Stopping appserver." if @debug
    @httpserv.stop if @httpserv and @httpserv.respond_to?(:stop)
    
    self.log_puts "Stopping threadpool." if @debug
    @threadpool.stop if @threadpool
    
    #This should be done first to be sure it finishes (else we have a serious bug).
    self.log_puts "Flush out loaded sessions." if @debug
    
    #Flush sessions and mails (only if the modules are loaded).
    self.flush_error_emails(:ignore_time => true) if self.respond_to?(:flush_error_emails)
    self.sessions_flush if self.respond_to?(:sessions_flush)
    self.mail_flush if self.respond_to?(:mail_flush)
    
    self.log_puts "Stopping done..." if @debug
  end
  
  #Stop running any more HTTP-requests - make them wait.
  def pause
    @paused += 1
  end
  
  #Unpause - start handeling HTTP-requests again.
  def unpause
    @paused -= 1
  end
  
  #Returns true if paued - otherwise false.
  def paused?
    return true if @paused > 0
    return false
  end
  
  #Will stop handeling any more HTTP-requests, run the proc given and return handeling HTTP-requests.
  def paused_exec
    raise "No block given." if !block_given?
    self.pause
    
    begin
      sleep 0.2 while @httpserv and @httpserv.working_count and @httpserv.working_count > 0
      @paused_mutex.synchronize do
        Timeout.timeout(15) do
          yield
        end
      end
    ensure
      self.unpause
    end
  end
  
  #Returns true if a HTTP-request is working. Otherwise false.
  def working?
    return true if @httpserv and @httpserv.working_count > 0
    return false
  end
  
  def self.data
    raise "Could not register current thread." if !Thread.current[:hayabusa]
    return Thread.current[:hayabusa]
  end
  
  #Sleeps until the server is stopped.
  def join
    raise "No http-server or http-server not running." if !@httpserv or !@httpserv.thread_accept
    
    begin
      @httpserv.thread_accept.join
      @httpserv.thread_restart.join if @httpserv and @httpserv.thread_restart
    rescue Interrupt => e
      STDOUT.puts "Trying to stop because of interrupt - please wait while various data is beging flushed."
      self.stop
    end
    
    if @should_restart
      loop do
        if @should_restart_done
          self.log_puts "Ending join because the restart is done."
          break
        end
        
        sleep 1
      end
    end
  end
  
  #Defines a variable as a method bound to the threads spawned by this instance of Hayabusa.
  def define_magic_var(method_name, var)
    @magic_vars[method_name] = var
    
    if !Object.respond_to?(method_name)
      Object.send(:define_method, method_name) do
        return Thread.current[:hayabusa][:hb].magic_vars[method_name] if Thread.current[:hayabusa] and Thread.current[:hayabusa][:hb]
        raise "Could not figure out the object: '#{method_name}'."
      end
    end
  end
  
  def define_magic_proc(method_name, &block)
    raise "No block given." if !block_given?
    @magic_procs[method_name] = block
    
    if !Object.respond_to?(method_name)
      Object.send(:define_method, method_name) do
        return Thread.current[:hayabusa][:hb].magic_procs[method_name].call(:hb => self) if Thread.current[:hayabusa] and Thread.current[:hayabusa][:hb]
        raise "Could not figure out the object: '#{method_name}'."
      end
    end
  end
  
  def translations
    if !@translations
      #Start the Knj::Gettext_threadded- and Knj::Translations modules for translations.
      self.log_puts "Loading Gettext and translations." if @debug
      @translations = Knj::Translations.new(:db => @db)
      @ob.requireclass(:Translation, :require => false, :class => Knj::Translations::Translation)
    end
    
    return @translations
  end
end