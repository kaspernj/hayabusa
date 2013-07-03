def _cookie
  return Thread.current[:hayabusa][:cookie] if Thread.current[:hayabusa]
end

def _get
  return Thread.current[:hayabusa][:get] if Thread.current[:hayabusa]
end

def _post
  return Thread.current[:hayabusa][:post] if Thread.current[:hayabusa]
end

def _meta
  return Thread.current[:hayabusa][:meta] if Thread.current[:hayabusa]
end

def _server
  return Thread.current[:hayabusa][:meta] if Thread.current[:hayabusa]
end

def _session
  return Thread.current[:hayabusa][:session].sess_data if Thread.current[:hayabusa] and Thread.current[:hayabusa][:session]
end

def _session_hash
  return Thread.current[:hayabusa][:session].edata if Thread.current[:hayabusa] and Thread.current[:hayabusa][:session]
end

def _session_obj
  return Thread.current[:hayabusa][:session] if Thread.current[:hayabusa] and Thread.current[:hayabusa][:session]
end

def _httpsession
  return Thread.current[:hayabusa][:httpsession] if Thread.current[:hayabusa]
end

def _httpsession_var
  return Thread.current[:hayabusa][:httpsession].httpsession_var if Thread.current[:hayabusa]
end

def _requestdata
  return Thread.current[:hayabusa] if Thread.current[:hayabusa]
end

def _request_hash
  return Thread.current[:hayabusa][:httpsession].request_hash if Thread.current[:hayabusa]
end

def _hb
  return Thread.current[:hayabusa][:hb] if Thread.current[:hayabusa]
end

def _vars
  return Thread.current[:hayabusa][:hb].vars if Thread.current[:hayabusa]
end

def _db
  return Thread.current[:hayabusa][:db] if Thread.current[:hayabusa] and Thread.current[:hayabusa][:db] #This is the default use from a .rhtml-file.
  return Thread.current[:hayabusa][:hb].db_handler if Thread.current[:hayabusa] and Thread.current[:hayabusa][:hb] #This is useually used when using autoload-argument for the appserver.
end

#This function makes it possible to define methods in ERubis-parsed files (else _buf-variable wouldnt be globally available).
def _buf
  return $stdout
end