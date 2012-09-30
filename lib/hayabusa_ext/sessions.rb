class Hayabusa
  def initialize_sessions
    @sessions = Tsafe::MonHash.new
  end
  
  #Returns or adds session based on idhash and meta-data.
  def session_fromid(ip, idhash, meta)
    ip = "bot" if idhash == "bot"
    
    if !@sessions.key?(idhash)
      session = @ob.get_by(:Session, "idhash" => idhash)
      if !session
        session = @ob.add(:Session, {
          :idhash => idhash,
          :user_agent => meta["HTTP_USER_AGENT"],
          :ip => ip
        })
      end
      
      hash = {}
      @sessions[idhash] = {
        :dbobj => session,
        :hash => hash
      }
    else
      session = @sessions[idhash][:dbobj]
      hash = @sessions[idhash][:hash]
    end
    
    raise ArgumentError, "Invalid IP." if ip != "bot" and !session.remember? and ip.to_s != session[:ip].to_s
    
    @sessions[idhash][:time_lastused] = Time.now
    return [session, hash]
  end
  
  #Generates a new session-ID by the meta data.
  def session_generate_id(meta)
    return Digest::MD5.hexdigest("#{Time.now.to_f}_#{meta["HTTP_HOST"]}_#{self.ip(:meta => meta)}_#{meta["HTTP_USER_AGENT"]}")
  end
  
  #Will make the session rememberable for a year. IP wont be checked any more.
  def session_remember
    httpsession = Thread.current[:hayabusa][:httpsession]
    raise "Could not figure out HTTP-session." if !httpsession
    session = httpsession.session
    raise "Could not get session-variable from HTTP-session." if !session
    session[:remember] = 1
    
    self.cookie(
      "name" => "HayabusaSession",
      "value" => _httpsession.session_id,
      "path" => "/",
      "expires" => Time.now + 32140800 #add around 12 months
    )
  end
  
  #Will make the session run out as soon as the user closes his browser.
  def session_dont_remember
    httpsession = Thread.current[:hayabusa][:httpsession]
    raise "Could not figure out HTTP-session." if !httpsession
    session = httpsession.session
    raise "Could not get session-variable from HTTP-session." if !session
    session[:remember] = 0
    
    self.cookie(
      "name" => "HayabusaSession",
      "value" => _httpsession.session_id,
      "path" => "/"
    )
  end
  
  #Writes all session-data to the database (normally it is cached in memory and not updated on change).
  def sessions_flush
    if @sessions
      @sessions.each do |session_hash, session_data|
        self.log_puts("Flushing session: #{session_data[:dbobj].id}") if @debug
        session_data[:dbobj].flush
      end
    end
  end
  
  #Writes all session-data and resets the hash.
  def sessions_reset
    self.sessions_flush
    @sessions = {}
  end
end