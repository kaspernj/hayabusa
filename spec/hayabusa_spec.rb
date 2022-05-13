require "spec_helper"

describe "Hayabusa" do
  require "rubygems"
  require "sqlite3" if RUBY_ENGINE != "jruby"
  require "json"
  require "rmagick"

  begin
    require "#{File.realpath(File.dirname(__FILE__))}/../../knjrbfw/lib/knjrbfw.rb"
  rescue LoadError
    require "knjrbfw"
  end

  require "#{File.realpath(File.dirname(__FILE__))}/../lib/hayabusa.rb"

  begin
    require "#{File.realpath(File.dirname(__FILE__))}/../../http2/lib/http2.rb"
    puts "Loaded custom version of Http2."
  rescue LoadError
    require "http2"
    puts "Loaded normal gem version of Http2."
  end

  db_path = "#{Knj::Os.tmpdir}/hayabusa_rspec.sqlite3"
  File.unlink(db_path) if File.exists?(db_path)

  db = Baza::Db.new(
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
    :db => db,
    :threadding => {
      :priority => -3
    }
  )

  $appserver.config[:handlers] << {
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

  $appserver.vars[:test] = "kasper"
  $appserver.define_magic_var(:_testvar1, "Kasper")
  $appserver.define_magic_var(:_testvar2, "Johansen")
  $appserver.start

  raise "Expected thread-pool-priority to be '-3' but it wasnt: '#{$appserver.threadpool.args[:priority]}'." if $appserver.threadpool.args[:priority] != -3

  http = Http2.new(:host => "localhost", :port => 80, :encoding_gzip => false, :debug => false) rescue nil

  $testmodes = [{
    :name => :standalone,
    :path_pre => "",
    :http => Http2.new(:host => "localhost", :port => 1515, :debug => false)
  }]

  if http
    $testmodes += [{
      :name => :cgi,
      :path_pre => "hayabusa_cgi_test/",
      :http => http
    },{
      :name => :fcgi,
      :path_pre => "hayabusa_fcgi_test/",
      :http => http
    }]
  end

  it "should be able to get multiple pictures" do
    require "base64"

    # Symlink 'image.rhtml' first.
    img_from_path = "#{Knj.knjrbfw_path}/webscripts/image.rhtml"
    img_to_path = "#{File.realpath("#{File.dirname(__FILE__)}/../pages")}/image.rhtml"

    raise "Invalid from path: '#{img_from_path}'." unless File.exists?(img_from_path)

    File.unlink(img_to_path) if File.symlink?(img_to_path)
    File.symlink(img_from_path, img_to_path)

    last_tdata = nil

    begin
      $testmodes.each do |tdata|
        last_tdata = tdata

        3.times do
          path = "#{File.dirname(__FILE__)}/../pages/testpic.jpeg"

          res = tdata[:http].get("#{tdata[:path_pre]}testpic.jpeg")
          res.body.bytesize.should eql(File.size(path))

          res.body.bytes.to_a.should eql(File.read(path).bytes.to_a)

          #puts "Getting forced image through #{tdata[:name]}"
          res = tdata[:http].get("#{tdata[:path_pre]}image.rhtml?force=true&path64=#{Base64.encode64("testpic.jpeg").to_s.strip}")

          #puts "Getting normal image through #{tdata[:name]}"
          res1 = tdata[:http].get("#{tdata[:path_pre]}image.rhtml?path64=#{Base64.encode64("image.png").to_s.strip}&rounded_corners=8&width=550")
          res1.contenttype.should eql("image/png")

          #puts "Getting exit-script through #{tdata[:name]}"
          res_exit = tdata[:http].get("#{tdata[:path_pre]}spec_exit.rhtml")
          res_exit.body.should eql("ExitOutput\n")
          res_exit.code.to_i.should eql(304)

          #puts "Getting normal image through #{tdata[:name]}"
          res2 = tdata[:http].get("#{tdata[:path_pre]}image.rhtml?path64=#{Base64.encode64("image.png").to_s.strip}&rounded_corners=8&width=550")
          res2.contenttype.should eql("image/png")

          res1.body.bytesize.should eql(res2.body.bytesize)
        end
      end
    rescue => e
      puts "Mode: #{last_tdata[:name]}" if last_tdata
      STDERR.puts e.inspect
      STDERR.puts e.backtrace
      raise e
    ensure
      File.unlink(img_to_path) if File.exists?(img_to_path)
    end
  end

  #it "should be able to handle custom urls" do
  #  $testmodes.each do |tdata|
  #    res = tdata[:http].get("#{tdata[:path_pre]}Kasper")
  #    raise "Expected data to be 'Test' in mode '#{tdata[:name]}' but it wasnt: '#{res.body}'." if res.body != "Test"
  #  end
  #end

  it "should be able to upload files" do
    $testmodes.each do |tdata|
      fpaths = {
        "fpath1" => "#{File.realpath(File.dirname(__FILE__))}/../pages/spec_thread_joins.rhtml",
        "fpath2" => "#{File.realpath(File.dirname(__FILE__))}/test_upload.xlsx"
      }

      res = tdata[:http].post_multipart(:url => "#{tdata[:path_pre]}spec_vars_post_fileupload.rhtml", :post => {
        "testfile1" => {
          :filename => "spec_thread_joins.rhtml",
          :fpath => fpaths["fpath1"]
        },
        "testfile2" => {
          :filename => "test_upload.xlsx",
          :fpath => fpaths["fpath2"]
        }
      })

      1.upto(2) do |count|
        data = Marshal.load(res.body)
        raise "No data returned?" unless data

        if count != 2
          key = "testfile#{count}"
          raise "Not defined in returned data: '#{key}' in '#{data}'." unless data.key?(key)
          if data[key]["val"] != File.read(fpaths["fpath#{count}"])
            File.open("/tmp/hayabusa_spec_testfile#{count}_1", "w") do |fp|
              fp.puts("Class: #{data["testfile#{count}"].class.name}")
              fp.write(data["testfile#{count}"])
            end

            File.open("/tmp/hayabusa_spec_testfile#{count}_2", "w") do |fp|
              fp.write(File.read(fpaths["fpath#{count}"]))
            end

            raise "Expected uploaded data for mode '#{tdata[:name]}' to be the same but it wasnt:\n\"#{data["testfile#{count}"]}\"\n\n\"#{File.read(fpaths["fpath#{count}"])}\""
          end
        end

        raise "Expected 'testfile' class to be 'Hayabusa::Http_session::Post_multipart::File_upload' in mode '#{tdata[:name]}' but it wasnt: '#{data["testfile#{count}"]["class"]}'." if data["testfile#{count}"]["class"] != "Hayabusa::Http_session::Post_multipart::File_upload"
      end
    end
  end

  it "should be able to handle a GET-request." do
    $testmodes.each do |tdata|
      res = tdata[:http].get("#{tdata[:path_pre]}spec.rhtml")
      raise "Unexpected HTML: '#{res.body}'." if res.body.to_s != "Test"

      #Check that URL-decoding are being done.
      res = tdata[:http].get("#{tdata[:path_pre]}spec.rhtml?choice=check_get_parse&value=#{Knj::Web.urlenc("gfx/nopic.png")}")
      raise "Unexpected HTML: '#{res.body}'." if res.body.to_s != "gfx/nopic.png"
    end
  end

  it "should be able to handle a HEAD-request." do
    #Http2 doesnt support head?
    #res = $http.head("spec.rhtml")
    #raise "HEAD-request returned content - it shouldnt?" if res.body.to_s.length > 0
  end

  it "should be able to handle a POST-request." do
    $testmodes.each do |tdata|
      res = tdata[:http].post(:url => "#{tdata[:path_pre]}spec.rhtml", :post => {
        "postdata" => "Test post"
      })
      raise "POST-request did not return expected data: '#{res.body}' for '#{tdata[:name]}' data: '#{res.body}'." if res.body.to_s.strip != "Test post"

      res = tdata[:http].post(:url => "#{tdata[:path_pre]}spec.rhtml?choice=dopostconvert", :post => {
        "postdata" => "Test post",
        "array" => ["a", "b", "d"]
      })
      data = JSON.parse(res.body)
      raise "Expected posted data restored but it wasnt: '#{data}'." if data["array"]["0"] != "a" or data["array"]["1"] != "b" or data["array"]["2"] != "d"
    end
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
    $testmodes.each do |tdata|
      res = tdata[:http].get("#{tdata[:path_pre]}spec.rhtml")
      raise "Normal header data could not be detected." if res.header("testheader") != "NormalHeader"
      raise "Raw header data could not be detected." if res.header("testraw") != "RawHeader"
    end
  end

  it "should be able to set and get multiple cookies at the same time." do
    $testmodes.each do |tdata|
      res = tdata[:http].get("#{tdata[:path_pre]}spec.rhtml?choice=test_cookie")
      raise res.body if res.body.to_s.length > 0

      res = tdata[:http].get("#{tdata[:path_pre]}spec.rhtml?choice=get_cookies")
      parsed = JSON.parse(res.body)

      raise "Unexpected value for 'TestCookie': '#{parsed["TestCookie"]}'." if parsed["TestCookie"] != "TestValue"
      raise "Unexpected value for 'TestCookie2': '#{parsed["TestCookie2"]}'." if parsed["TestCookie2"] != "TestValue2"
      raise "Unexpected value for 'TestCookie3': '#{parsed["TestCookie3"]}'." if parsed["TestCookie3"] != "TestValue 3 "
    end
  end

  it "should be able to run the rspec_threadded_content test correctly." do
    $testmodes.each do |tdata|
      res = tdata[:http].get("#{tdata[:path_pre]}spec_threadded_content.rhtml")
      raise "Expected body to be '12345678910' for mode '#{tdata[:name]}' but it wasnt: '#{res.body.to_s}'." if res.body.to_s != "12345678910"
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

  it "should be able to join threads tarted from _hb.thread." do
    $testmodes.each do |tdata|
      res = tdata[:http].get("#{tdata[:path_pre]}spec_thread_joins.rhtml")
      raise res.body if res.body.to_s != "12345"
    end
  end

  it "should be able to properly parse special characters in post-requests." do
    $testmodes.each do |tdata|
      res = tdata[:http].post(:url => "#{tdata[:path_pre]}spec_vars_post.rhtml", :post => {
        "test" => "123+456%789%20"
      })
      data = JSON.parse(res.body)
      raise res.body if data["test"] != "123+456%789%20"
    end
  end

  it "should be able to do logging" do
    class ::TestModels
      class Person < Hayabusa::Datarow

      end
    end

    Hayabusa::Revision.new.init_db("db" => $appserver.db, "schema" => {
      "tables" => {
        "Person" => {
          columns: [
            {name: "id", type: "int", autoincr: true, primarykey: true},
            {name: "name", type: "varchar"}
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

  it "should handle multi-threadding well" do
    ts = []
    es = []

    #Execute multiple threads to test FCGI-proxy and thread-safety.
    1.upto(5) do
      $testmodes.each do |tdata|
        ts << Thread.new do
          begin
            res = tdata[:http].post(:url => "#{tdata[:path_pre]}spec_vars_post.rhtml", :post => {
              "test_special_chars" => "1%23+-456",
              "var" => {
                0 => 1,
                1 => 2,
                3 => {
                  "kasper" => 5,
                  "arr" => ["a", "b", "c"]
                }
              }
            })

            begin
              data = JSON.parse(res.body)
            rescue
              raise "Could not parse JSON from result: '#{res.body}'."
            end

            begin
              raise "Expected hash to be a certain way: '#{data}'." if data["var"]["0"] != "1" or data["var"]["1"] != "2" or data["var"]["3"]["kasper"] != "5" or data["var"]["3"]["arr"]["0"] != "a" or data["var"]["3"]["arr"]["1"] != "b"
            rescue => e
              raise "Error when parsing result: '#{data}'."
            end

            raise "Expected 'test_special_chars' to be '1%23+-456' but it wasnt: '#{data["test_special_chars"]}'." if data["test_special_chars"] != "1%23+-456"

            res = tdata[:http].get("#{tdata[:path_pre]}spec_threadded_content.rhtml")
            raise "Expected body to be '12345678910' but it was: '#{res.body}'." if res.body != "12345678910"

            res = tdata[:http].get("#{tdata[:path_pre]}spec_vars_get.rhtml?var[]=1&var[]=2&var[]=3&var[3][kasper]=5")
            data = JSON.parse(res.body)
            raise "Expected hash to be a certain way: '#{data}'." if data["var"]["0"] != "1" or data["var"]["1"] != "2" or data["var"]["3"]["kasper"] != "5"



            res = tdata[:http].get("#{tdata[:path_pre]}spec_vars_header.rhtml")
            raise "Expected header 'testheader' to be 'TestValue' but it wasnt: '#{res.header("testheader")}'." if res.header("testheader") != "TestValue"
          rescue => e
            es << e
            puts e.inspect
            puts e.backtrace
          end
        end
      end

      ts.each do |t|
        t.join
      end

      es.each do |e|
        raise e
      end
    end
  end

  it "should be able to stop." do
    $appserver.stop
  end
end
