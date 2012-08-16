require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Hayabusa" do
  it "two simultanious request should be handeled by the same process - one should proxy the request" do
    require "rubygems"
    require "http2"
    require "json"
    
    Http2.new(:host => "localhost") do |http1|
      Http2.new(:host => "localhost") do |http2|
        res1 = nil
        res2 = nil
        
        t1 = Thread.new do
          res1 = http1.get(:url => "hayabusa_fcgi_test/sleeper.rhtml")
        end
        
        t2 = Thread.new do
          res2 = http2.get(:url => "hayabusa_fcgi_test/sleeper.rhtml")
        end
        
        t1.join
        t2.join
        
        pid1 = res1.body.to_i
        pid2 = res2.body.to_i
        
        raise "Expected PIDs to be the same: '#{res1.body}', '#{res2.body}'." if pid1 != pid2 or pid1 == 0 or pid2 == 0
      end
    end
  end
end
