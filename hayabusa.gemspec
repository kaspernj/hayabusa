Gem::Specification.new do |s|
  s.name = "hayabusa"
  s.version = "0.0.28"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Kasper Stöckel"]
  s.description = "A threadded web/app-server that focuses on threadding, shared ressources, speed and more."
  s.email = "k@spernj.org"
  s.executables = ["check_running.rb", "hayabusa_benchmark.rb", "hayabusa_cgi.rb", "hayabusa_fcgi.fcgi", "hayabusa_fcgi.rb", "hayabusa_fcgi_server.rb", "hayabusa_spec_restart.rb", "knjappserver_start.rb"]
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.md"
  ]
  s.files = Dir["{include,lib}/**/*"] + ["Rakefile"]
  s.homepage = "http://github.com/kaspernj/hayabusa"
  s.licenses = ["MIT"]
  s.rubygems_version = "2.2.2"
  s.summary = "A threadded web/app-server that supports stand-alone, CGI and FCGI-modes."

  s.add_runtime_dependency(%q<baza>, [">= 0.0.38"])
  s.add_runtime_dependency(%q<knjrbfw>, [">= 0.0.110"])
  s.add_runtime_dependency(%q<wref>, [">= 0.0.6"])
  s.add_runtime_dependency(%q<erubis>, [">= 0"])
  s.add_runtime_dependency(%q<mail>, [">= 0"])
  s.add_runtime_dependency(%q<datet>, [">= 0"])
  s.add_runtime_dependency(%q<http2>, [">= 0"])
  s.add_runtime_dependency(%q<tpool>, [">= 0"])
  s.add_runtime_dependency(%q<ruby_process>, [">= 0"])
  s.add_development_dependency(%q<json>, [">= 0"])
  s.add_development_dependency(%q<rspec>, [">= 2.3.0"])
  s.add_development_dependency(%q<bundler>, [">= 1.0.0"])
  s.add_development_dependency(%q<rmagick>, [">= 0"])
  s.add_development_dependency(%q<sqlite3>, [">= 0"])
  s.add_development_dependency(%q<php4r>, [">= 0"])
end
