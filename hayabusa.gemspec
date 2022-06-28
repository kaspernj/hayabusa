Gem::Specification.new do |s|
  s.name = "hayabusa"
  s.version = "0.0.30"

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
  s.files = Dir["{include,lib,pages}/**/*"] + ["Rakefile"]
  s.homepage = "http://github.com/kaspernj/hayabusa"
  s.licenses = ["MIT"]
  s.summary = "A threadded web/app-server that supports stand-alone, CGI and FCGI-modes."

  s.add_runtime_dependency("baza", ">= 0.0.38")
  s.add_runtime_dependency("datet", ">= 0")
  s.add_runtime_dependency("erubis", ">= 0")
  s.add_runtime_dependency("http2", ">= 0")
  s.add_runtime_dependency("knjrbfw", ">= 0.0.114")
  s.add_runtime_dependency("mail", ">= 0")
  s.add_runtime_dependency("ruby_process", ">= 0")
  s.add_runtime_dependency("tpool", ">= 0")
  s.add_runtime_dependency("wref", ">= 0.0.6")
  s.add_development_dependency("bundler", ">= 1.0.0")
  s.add_development_dependency("json", ">= 0")
  s.add_development_dependency("php4r", ">= 0")
  s.add_development_dependency("rmagick", ">= 0")
  s.add_development_dependency("rspec", ">= 2.3.0")
  s.add_development_dependency("rubocop")
  s.add_development_dependency("rubocop-performance")
  s.add_development_dependency("rubocop-rake")
  s.add_development_dependency("rubocop-rspec")
  s.add_development_dependency("sqlite3", ">= 0")
end
