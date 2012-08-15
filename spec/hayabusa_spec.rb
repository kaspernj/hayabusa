require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Hayabusa" do
  it "should be able to start a sample-server" do
    require "rubygems"
    require "hayabusa"
    require "knjrbfw"
    require "sqlite3" if RUBY_ENGINE != "jruby"
    
    db_path = "#{Knj::Os.tmpdir}/hayabusa_rspec.sqlite3"
    File.unlink(db_path) if File.exists?(db_path)
    
    db = Knj::Db.new(
      :type => "sqlite3",
      :path => db_path,
      :return_keys => "symbols"
    )
    
    $appserver = Hayabusa.new(
      :debug => false,
      :title => "SpecTest",
      :port => 1515,
      :doc_root => "#{File.dirname(__FILE__)}/../pages",
      :locales_gettext_funcs => true,
      :locale_default => "da_DK",
      :db => db
    )
    
    $appserver.vars[:test] = "kasper"
    $appserver.define_magic_var(:_testvar1, "Kasper")
    $appserver.define_magic_var(:_testvar2, "Johansen")
    $appserver.start
  end
  
  it "should be able to handle a GET-request." do
    #Check that we are able to perform a simple GET request and get the correct data back.
    require "http2"
    $http = Http2.new(:host => "localhost", :port => 1515)
    
    res = $http.get("spec.rhtml")
    raise "Unexpected HTML: '#{res.body}'." if res.body.to_s != "Test"
    
    #Check that URL-decoding are being done.
    res = $http.get("spec.rhtml?choice=check_get_parse&value=#{Knj::Web.urlenc("gfx/nopic.png")}")
    raise "Unexpected HTML: '#{res.body}'." if res.body.to_s != "gfx/nopic.png"
  end
  
  it "should be able to handle a HEAD-request." do
    #Http2 doesnt support head?
    #res = $http.head("/spec.rhtml")
    #raise "HEAD-request returned content - it shouldnt?" if res.body.to_s.length > 0
  end
  
  it "should be able to handle a POST-request." do
    res = $http.post(:url => "spec.rhtml", :post => {
      "postdata" => "Test post"
    })
    raise "POST-request did not return expected data: '#{res.body}'." if res.body.to_s.strip != "Test post"
    
    res = $http.post(:url => "spec.rhtml?choice=dopostconvert", :post => {
      "postdata" => "Test post",
      "array" => ["a", "b", "d"]
    })
    data = JSON.parse(res.body)
    raise "Expected posted data restored but it wasnt: '#{data}'." if data["array"]["0"] != "a" or data["array"]["1"] != "b" or data["array"]["2"] != "d"
  end
  
  it "should be able to join the server so other tests can be made manually." do
    begin
      Timeout.timeout(1) do
        $appserver.join
        raise "Appserver didnt join."
      end
    rescue Timeout::Error
      #ignore.
    end
  end
  
  it "should be able to use the header-methods." do
    res = $http.get("spec.rhtml")
    raise "Normal header data could not be detected." if res.header("testheader") != "NormalHeader"
    raise "Raw header data could not be detected." if res.header("testraw") != "RawHeader"
  end
  
  it "should be able to set and get multiple cookies at the same time." do
    require "json"
    
    res = $http.get("spec.rhtml?choice=test_cookie")
    raise res.body if res.body.to_s.length > 0
    
    res = $http.get("spec.rhtml?choice=get_cookies")
    parsed = JSON.parse(res.body)
    
    raise "Unexpected value for 'TestCookie': '#{parsed["TestCookie"]}'." if parsed["TestCookie"] != "TestValue"
    raise "Unexpected value for 'TestCookie2': '#{parsed["TestCookie2"]}'." if parsed["TestCookie2"] != "TestValue2"
    raise "Unexpected value for 'TestCookie3': '#{parsed["TestCookie3"]}'." if parsed["TestCookie3"] != "TestValue 3 "
  end
  
  it "should be able to run the rspec_threadded_content test correctly." do
    res = $http.get("spec_threadded_content.rhtml")
    
    if res.body != "12345678910"
      raise res.body.to_s
    end
  end
  
  it "should be able to add a timeout." do
    $break_timeout = false
    timeout = $appserver.timeout(:time => 1) do
      $break_timeout = true
    end
    
    Timeout.timeout(2) do
      loop do
        break if $break_timeout
        sleep 0.1
      end
    end
  end
  
  it "should be able to stop a timeout." do
    $timeout_runned = false
    timeout = $appserver.timeout(:time => 1) do
      $timeout_runned = true
    end
    
    sleep 0.5
    timeout.stop
    
    begin
      Timeout.timeout(1.5) do
        loop do
          raise "The timeout ran even though stop was called?" if $timeout_runned
          sleep 0.1
        end
      end
    rescue Timeout::Error
      #the timeout didnt run - and it shouldnt so dont do anything.
    end
  end
  
  it "should be able to join threads tarted from _kas.thread." do
    res = $http.get("spec_thread_joins.rhtml")
    raise res.body if res.body.to_s != "12345"
  end
  
  it "should be able to properly parse special characters in post-requests." do
    res = $http.post(:url => "spec_post.rhtml", :post => {
      "test" => "123+456%789%20"
    })
    raise res.body if res.body != "123+456%789%20"
  end
  
  it "should be able to do logging" do
    class ::TestModels
      class Person < Knj::Datarow
        
      end
    end
    
    Knj::Db::Revision.new.init_db("db" => $appserver.db, "schema" => {
      "tables" => {
        "Person" => {
          "columns" => [
            {"name" => "id", "type" => "int", "autoincr" => true, "primarykey" => true},
            {"name" => "name", "type" => "varchar"}
          ]
        }
      }
    })
    
    ob = Knj::Objects.new(
      :db => $appserver.db,
      :datarow => true,
      :require => false,
      :module => ::TestModels
    )
    
    person = ob.add(:Person, :name => "Kasper")
    
    $appserver.log("This is a test", person)
    logs = $appserver.ob.list(:Log, "object_lookup" => person).to_a
    raise "Expected count to be 1 but got: #{logs.length}" if logs.length != 1
    
    $appserver.logs_delete(person)
    
    logs = $appserver.ob.list(:Log, "object_lookup" => person).to_a
    raise "Expected count to be 0 but got: #{logs.length}" if logs.length != 0
  end
  
  it "should be able to stop." do
    $appserver.stop
  end
end
