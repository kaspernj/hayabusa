require "monitor"

class Hayabusa
  attr_reader :mails_waiting
  
  def initialize_mailing
    require "knj/autoload/ping"
    
    @mails_waiting = []
    @mails_mutex = Monitor.new
    @mails_queue_mutex = Monitor.new
    @mails_timeout = self.timeout(:time => @config[:mailing_time], &self.method(:mail_flush))
  end
  
  #Queue a mail for sending. Possible keys are: :subject, :from, :to, :text and :html.
  def mail(mail_args)
    raise "'smtp_args' has not been given for the Hayabusa." if !@config[:smtp_args]
    
    @mails_queue_mutex.synchronize do
      count_wait = 0
      while @mails_waiting.length > 100
        if count_wait >= 30
          raise "Could not send email - too many emails was pending and none of them were being sent?"
        end
        
        count_wait += 1
        sleep 1
      end
      
      mailobj = Hayabusa::Mail.new({:hb => self, :errors => {}, :status => :waiting}.merge(mail_args))
      STDOUT.print "Added mail '#{mailobj.__id__}' to the mail-send-queue.\n" if debug
      @mails_waiting << mailobj
      
      #Try to send right away and raise error instantly if something happens if told to do so.
      if mail_args[:now] or @config[:mailing_instant]
        self.mail_flush
        raise mailobj.args[:error] if mailobj.args[:error]
      end
      
      return mailobj
    end
  end
  
  #Sends all queued mails to the respective servers, if we are online.
  def mail_flush
    @mails_mutex.synchronize do
      STDOUT.print "Flushing mails.\n" if @debug
      
      if @mails_waiting.length <= 0
        STDOUT.print "No mails to flush - skipping.\n" if @debug
        return false
      end
      
      STDOUT.print "Trying to ping Google to figure out if we are online...\n" if @debug
      status = Ping.pingecho("google.dk", 10, 80)
      if !status
        STDOUT.print "We are not online - skipping mail flush.\n"
        return false  #Dont run if we dont have a connection to the internet and then properly dont have a connection to the SMTP as well.
      end
      
      #Use subprocessing to avoid the mail-framework (activesupport and so on, also possible memory leaks in those large frameworks).
      STDOUT.print "Starting subprocess for mailing.\n" if @debug
      Knj::Process_meta.new("debug" => @debug, "debug_err" => true, "id" => "hayabusa_mailing") do |subproc|
        subproc.static("Object", "require", "rubygems")
        subproc.static("Object", "require", "mail")
        subproc.static("Object", "require", "#{@config[:knjrbfw_path]}knjrbfw")
        subproc.static("Object", "require", "knj/autoload")
        
        STDOUT.print "Flushing emails." if @debug
        @mails_waiting.each do |mail|
          begin
            STDOUT.print "Sending email: #{mail.__id__}\n" if @debug
            if mail.send("proc" => subproc)
              STDOUT.print "Email sent: #{mail.__id__}\n" if @debug
              @mails_waiting.delete(mail)
            end
          rescue Timeout::Error
            #ignore - 
          rescue => e
            @mails_waiting.delete(mail)
            self.handle_error(e, {:email => false})
          end
          
          sleep 1 #sleep so we dont take up too much bandwidth.
        end
      end
      
      return nil
    end
  end
  
  #This class represents the queued mails.
  class Mail
    attr_reader :args
    
    def initialize(args)
      @args = args
      
      raise "No hayabusa-object was given (as :hb)." if !@args[:hb].is_a?(Hayabusa)
      raise "No :to was given." if !@args[:to]
      raise "No content was given (:html or :text)." if !@args[:html] and !@args[:text]
      
      #Test from-argument.
      if !@args[:from].to_s.strip.empty?
        #Its ok.
      elsif !@args[:hb].config[:error_report_from].to_s.strip.empty?
        @args[:from] = @args[:hb].config[:error_report_from]
      else
        raise "Dont know where to take the 'from'-paramter from - none given in appserver config or mail-method-arguments?"
      end
    end
    
    #Returns a key from the arguments.
    def [](key)
      return @args[key]
    end
    
    #Sends the email to the receiver.
    def send(args = {})
      STDOUT.print "Sending mail '#{__id__}'.\n" if @args[:hb].debug
      
      if args["proc"]
        args["proc"].static("Object", "require", "knj/mailobj")
        mail = args["proc"].new("Knj::Mailobj", @args[:hb].config[:smtp_args])
        mail._pm_send_noret("to=", @args[:to])
        mail._pm_send_noret("subject=", @args[:subject]) if @args[:subject]
        mail._pm_send_noret("html=", Knj::Strings.email_str_safe(@args[:html])) if @args[:html]
        mail._pm_send_noret("text=", Knj::Strings.email_str_safe(@args[:text])) if @args[:text]
        mail._pm_send_noret("from=", @args[:from])
        mail._pm_send_noret("send")
      else
        mail = Knj::Mailobj.new(@args[:hb].config[:smtp_args])
        mail.to = @args[:to]
        mail.subject = @args[:subject] if @args[:subject]
        mail.html = Knj::Strings.email_str_safe(@args[:html]) if @args[:html]
        mail.text = Knj::Strings.email_str_safe(@args[:text]) if @args[:text]
        mail.from = @args[:from]
        mail.send
      end
      
      @args[:status] = :sent
      STDOUT.print "Sent email #{self.__id__}\n" if @args[:hb].debug
      return true
    rescue => e
      if @args[:hb].debug
        STDOUT.print "Could not send email.\n"
        STDOUT.puts e.inspect
        STDOUT.puts e.backtrace
      end
      
      @args[:errors][e.class.name] = {:count => 0} if !@args[:errors].has_key?(e.class.name)
      @args[:errors][e.class.name][:count] += 1
      raise e if @args[:errors][e.class.name][:count] >= 5
      @args[:status] = :error
      @args[:error] = e
      
      return false
    end
  end
end