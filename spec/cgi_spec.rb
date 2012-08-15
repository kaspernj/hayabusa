require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Hayabusa" do
  it "should be able to start a sample-server" do
    require "rubygems"
    require "http2"
    require "json"
    
    Http2.new(:host => "localhost") do |http|
      res = http.post(:url => "hayabusa_cgi_test/vars_post_test.rhtml", :post => {
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
        data = JSON.parse(res.body.strip)
      rescue JSON::GeneratorError
        raise "Could not parse JSON from result: '#{res.body.strip}'."
      end
      
      begin
        raise "Expected hash to be a certain way: '#{data}'." if data["var"]["0"] != "1" or data["var"]["1"] != "2" or data["var"]["3"]["kasper"] != "5" or data["var"]["3"]["arr"]["0"] != "a" or data["var"]["3"]["arr"]["1"] != "b"
      rescue => e
        raise "Error when parsing result: '#{data}'."
      end
      
      
      res = http.get("hayabusa_cgi_test/threadded_content_test.rhtml")
      raise "Expected body to be '123456' but it was: '#{res.body.strip}'." if res.body.strip != "123456"
      
      res = http.get("hayabusa_cgi_test/vars_get_test.rhtml?var[]=1&var[]=2&var[]=3&var[3][kasper]=5")
      data = JSON.parse(res.body.strip)
      raise "Expected hash to be a certain way: '#{data}'." if data["var"]["0"] != "1" or data["var"]["1"] != "2" or data["var"]["3"]["kasper"] != "5"
    end
  end
end
