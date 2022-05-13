require "rubygems"
require "rmagick"

Hayabusa::FCGI_CONF = {
  :hayabusa => {
    :title => "Fcgi_test",
    :doc_root => File.realpath(File.dirname(__FILE__)),
    :handlers_extra => [{
      :regex => /^\/Kasper$/,
      :callback => proc{|data|
        data[:httpsession].page_path = nil

        eruby = data[:httpsession].eruby
        eruby.connect(:on_error) do |e|
          _hb.handle_error(e)
        end

        eruby.import("#{File.dirname(__FILE__)}/../pages/spec.rhtml")
      }
    }]
  }
}