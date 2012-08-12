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
      :debug => true,
      :title => "SpecTestCustomUrls",
      :port => 1515,
      :doc_root => "#{File.dirname(__FILE__)}/../lib/pages",
      :locales_gettext_funcs => true,
      :locale_default => "da_DK",
      :db => db
    )
    
    $appserver.start
  end
  
  it "should be able to stop." do
    $appserver.stop
  end
end
