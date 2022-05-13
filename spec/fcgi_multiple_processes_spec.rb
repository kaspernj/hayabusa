require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Hayabusa" do
  xit "should handle sessions correctly under stressed conditions" do
    require "knjrbfw"
    Knj.gem_require(:Http2)
    require "json"

    ts = []
    errs = []

    1.upto(10) do |t_i|
      ts << Thread.new do
        if t_i == 1
          debug = true
        else
          debug = false
        end

        begin
          session_id = nil
          hayabusa_session_id = nil
          session_hash_obj_id = nil

          Http2.new(:host => "localhost", :user_agent => "Client#{t_i}", :debug => false) do |http|
            1.upto(25) do |request_i|
              res = http.get(:url => "hayabusa_fcgi_test/spec_multiple_threads.rhtml")

              begin
                data_json = JSON.parse(res.body)
              rescue => e
                raise "Could not parse result as JSON: '#{res.body}'."
              end

              data = {}
              data_json.each do |key, val|
                data["#{key.to_s}"] = "#{val.to_s}"
              end

              if request_i == 1
                hayabusa_session_id = data["cookie"]["HayabusaSession"]
                session_hash_obj_id = data["session_hash_id"]
                session_id = data["session_id"]
              end

              #puts "request-i: #{request_i}, data-request-count: #{data["request_count"]}, hash-id: #{data["session_hash_id"]}" if debug

              #Check 'HayabusaSession'-cookie.
              raise "No 'HayabusaSession'-cookie?" if !data["cookie"]["HayabusaSession"]
              raise "Expected 'HayabusaSession'-cookie to be '#{hayabusa_session_id}' but it wasnt: '#{data["cookie"]["HayabusaSession"]}' (#{data["cookie"]})." if hayabusa_session_id != data["cookie"]["HayabusaSession"]

              #Check session-hash-object-ID.
              raise "No 'session_hash_id' from request: '#{data}'." if data["session_hash_id"].to_s.strip.empty?
              raise "Expected session-hash-object-ID to be '#{session_hash_obj_id}' but it wasnt: '#{data["session_hash_id"]}'." if session_hash_obj_id != data["session_hash_id"] or !session_hash_obj_id


              #Check session-object-ID.
              raise "Expected session-ID to be '#{session_id}' but it wasnt: '#{data["session_id"]}' for request '#{request_i}'." if session_id != data["session_id"]
              raise "Expected request-count for session to be the same as on the client: '#{request_i}' but it wasnt: '#{data["request_count"]}'." if data["request_count"].to_i != request_i
            end
          end
        rescue => e
          errs << e
        end
      end
    end

    ts.each do |t|
      t.join
    end

    errs.each do |e|
      raise e
    end
  end

  xit "two simultanious request should be handeled by the same process - one should proxy the request" do
    Knj.gem_require(:Http2, "http2")
    require "json"

    Http2.new(:host => "localhost") do |http1|
      Http2.new(:host => "localhost") do |http2|
        res1 = nil
        res2 = nil

        t1 = Thread.new do
          res1 = http1.get(:url => "hayabusa_fcgi_test/spec_sleeper.rhtml")
        end

        t2 = Thread.new do
          res2 = http2.get(:url => "hayabusa_fcgi_test/spec_sleeper.rhtml")
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
