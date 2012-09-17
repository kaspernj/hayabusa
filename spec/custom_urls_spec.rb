require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Hayabusa" do
  it "should be able to start a sample-server" do
    require "rubygems"
    require "knjrbfw"
    require "hayabusa"
    require "http2"
    require "sqlite3" if RUBY_ENGINE != "jruby"
    require "json"
    
    db_path = "#{Knj::Os.tmpdir}/hayabusa_rspec.sqlite3"
    File.unlink(db_path) if File.exists?(db_path)
    
    db = Knj::Db.new(
      :type => "sqlite3",
      :path => db_path,
      :return_keys => "symbols"
    )
    
    $appserver = Hayabusa.new(
      :debug => false,
      :title => "SpecTestCustomUrls",
      :port => 1515,
      :doc_root => "#{File.dirname(__FILE__)}/../pages",
      :locales_gettext_funcs => true,
      :locale_default => "da_DK",
      :db => db,
      :handlers => [
        {
          :regex => /^\/Kasper$/,
          :callback => proc{|data|
            data[:httpsession].page_path = nil
            
            eruby = data[:httpsession].eruby
            eruby.connect(:on_error) do |e|
              _hb.handle_error(e)
            end
            
            eruby.import("#{File.dirname(__FILE__)}/../pages/spec.rhtml")
          }
        }
      ]
    )
    
    $appserver.start
  end
  
  it "should be able to handle custom urls" do
    puts "Connecting."
    Http2.new(:host => "localhost", :port => 1515) do |http|
      puts "Getting result."
      res = http.get("Kasper")
      raise "Expected data to be 'Test' but it wasnt: '#{res.body}'." if res.body != "Test"
    end
  end
  
  it "should be able to stop." do
    $appserver.stop
  end
end
