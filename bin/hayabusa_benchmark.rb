#!/usr/bin/env ruby

Dir.chdir(File.dirname(__FILE__))

require "optparse"
require "sqlite3" if RUBY_ENGINE != "jruby"

begin
  args = {
    :filename => "benchmark.rhtml"
  }
  
  OptionParser.new do |opts|
    opts.banner = "Usage: benchmark.rb [options]"
    
    opts.on("-f FILENAME", "--file FILENAME", "The filename that should be requested from the server.") do |t|
      args[:filename] = t
    end
    
    opts.on("-k PATH", "--knjrbfw PATH", "The path of knjrbfw if it should not be loaded from gems.") do |path|
      args[:knjrbfw_path] = path
    end
  end.parse!
end

db_path = "#{File.dirname(__FILE__)}/benchmark_db.sqlite3"

appserver_args = {
  :debug => false,
  :port => 15081,
  :doc_root => "#{File.dirname(__FILE__)}/../pages",
  :db_args => {
    :type => "sqlite3",
    :path => db_path,
    :return_keys => "symbols"
  }
}

require "rubygems"
require "erubis"
require "#{args[:knjrbfw_path]}/knjrbfw.rb"
require "../hayabusa.rb"

if args[:knjrbfw_path]
  appserver_args[:knjrbfw_path] = args[:knjrbfw_path]
else
  require "knjrbfw"
end

require "knj/autoload"

appsrv = Hayabusa.new(appserver_args)
appsrv.start

count_requests = 0
1.upto(50) do |count_thread|
  Knj::Thread.new(count_thread) do |count_thread|
    print "Thread #{count_thread} started.\n"
    
    http = Http2.new(
      :host => "localhost",
      :port => 15081,
      :user_agent => "Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.1; debugid:#{count_thread}) Gecko/20060111 Firefox/3.6.0.1",
      :debug => false
    )
    
    loop do
      resp = http.get(:url => args[:filename])
      count_requests += 1
      raise "Invalid code: #{resp.code}\n" if resp.code.to_i != 200
    end
  end
end

loop do
  last_count = count_requests
  sleep 1
  counts_betw = count_requests - last_count
  print "#{counts_betw} /sec\n"
end

appsrv.join