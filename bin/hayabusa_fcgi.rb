#!/usr/bin/ruby

#This scripts start an appserver, executes a HTTP-request for every FCGI-request and terminates when FCGI terminates.
#Good for programming appserver-supported projects that doesnt need threadding without running an appserver all the time.

#It doesnt support shared threadding or objects because multiple instances in form of processes will be executed.

#Its a bit slower because it needs to flush writes to the database at end of every request and re-read them on spawn, because multiple instances might be present.

require "rubygems"
require "knjrbfw"
require "http2"
require "tsafe"
require "fcgi"

require "#{File.dirname(Knj::Os.realpath(__FILE__))}/../hayabusa.rb"

class Hayabusa
  def self.fcgi_start(cgi)
    raise "No HTTP_KNJAPPSERVER_CGI_CONFIG-header was given." if !cgi.env_table["HTTP_KNJAPPSERVER_CGI_CONFIG"]
    require cgi.env_table["HTTP_KNJAPPSERVER_CGI_CONFIG"]
    
    begin
      conf = Hayabusa::CGI_CONF
    rescue NameError
      raise "No 'Hayabusa::CGI_CONF'-constant was spawned by '#{cgi.env_table["HTTP_KNJAPPSERVER_CGI_CONFIG"]}'."
    end
    
    hayabusa_conf = Hayabusa::CGI_CONF["hayabusa"]
    hayabusa_conf.merge!(
      :cmdline => false,
      :port => 0 #Ruby picks random port and we get the actual port after starting the appserver.
    )
    
    hayabusa = Hayabusa.new(hayabusa_conf)
    hayabusa.start
    
    port = hayabusa.port
    http = Http2.new(:host => "localhost", :port => port)
    
    return [hayabusa, http]
  end
  
  def self.convert_fcgi_post(params)
    post_hash = {}
    
    params.each do |key, val|
      post_hash[key] = val.first
    end
    
    return post_hash
  end
end

hayabusa = nil
port = nil
http = nil
thread_spawn = nil
loadfp = "#{File.basename(__FILE__).slice(0..-6)}.rhtml"

FCGI.each_cgi do |cgi|
  begin
    $cgi = cgi
    
    if !hayabusa
      hayabusa, http = Hayabusa.fcgi_start(cgi)
    end
    
    thread_spawn.join if thread_spawn
    
    #FCGI will keep resetting the stdout. Force it to appserver instead.
    $stdout = hayabusa.cio
    
    headers = {}
    cgi.env_table.each do |key, val|
      if key[0, 5] == "HTTP_" and key != "HTTP_KNJAPPSERVER_CGI_CONFIG"
        key = Php4r.ucwords(key[5, key.length].gsub("_", " ")).gsub(" ", "-")
        headers[key] = val
      end
    end
    
    #Make request.
    if cgi.env_table["PATH_INFO"].length > 0 and cgi.env_table["PATH_INFO"] != "/"
      url = cgi.env_table["PATH_INFO"][1, cgi.env_table["PATH_INFO"].length]
    else
      url = "index.rhtml"
    end
    
    if cgi.env_table["QUERY_STRING"].to_s.length > 0
      url << "?#{cgi.env_table["QUERY_STRING"]}"
    end
    
    #cgi.print "Content-Type: text/html\r\n"
    #cgi.print "\r\n"
    #cgi.print Php4r.print_r(cgi.params, true)
    
    if cgi.request_method == "POST" and cgi.content_type.to_s.downcase.index("multipart/form-data") != nil
      count = 0
      http.post_multipart(:url => url, :post => Hayabusa.convert_fcgi_post(cgi.params),
        :default_headers => headers,
        :cookies => false,
        :on_content => proc{|line|
          cgi.print(line) if count > 0
          count += 1
        }
      )
    elsif cgi.request_method == "POST"
      count = 0
      http.post(:url => url, :post => Hayabusa.convert_fcgi_post(cgi.params),
        :default_headers => headers,
        :cookies => false,
        :on_content => proc{|line|
          cgi.print(line) if count > 0
          count += 1
        }
      )
    else
      count = 0
      http.get(:url => url,
        :default_headers => headers,
        :cookies => false,
        :on_content => proc{|line|
          cgi.print(line) if count > 0
          count += 1
        }
      )
    end
    
    thread_spawn = Thread.new do
      hayabusa.sessions_reset
    end
  rescue Exception => e
    cgi.print "Content-Type: text/html\r\n"
    cgi.print "\r\n"
    cgi.print Knj::Errors.error_str(e, {:html => true})
  end
end