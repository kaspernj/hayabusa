Gem::Specification.new do |s|
  s.name = "hayabusa"
  s.version = "0.0.30"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Kasper Stöckel"]
  s.description = "A threadded web/app-server that focuses on threadding, shared ressources, speed and more."
  s.email = "kasper@diestoeckels.de"
  s.executables = ["check_running.rb", "hayabusa_benchmark.rb", "hayabusa_cgi.rb", "hayabusa_fcgi.fcgi", "hayabusa_fcgi.rb", "hayabusa_fcgi_server.rb", "hayabusa_spec_restart.rb", "knjappserver_start.rb"]
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.md"
  ]
  s.files = Dir["{include,lib,pages}/**/*"] + ["Rakefile"]
  s.homepage = "http://github.com/kaspernj/hayabusa"
  s.licenses = ["MIT"]
  s.summary = "A threadded web/app-server that supports stand-alone, CGI and FCGI-modes."

  s.add_dependency("baza", ">= 0.0.38")
  s.add_dependency("datet", ">= 0")
  s.add_dependency("erubis", ">= 0")
  s.add_dependency("http2", ">= 0")
  s.add_dependency("knjrbfw", ">= 0.0.114")
  s.add_dependency("mail", ">= 0")
  s.add_dependency("ruby_process", ">= 0")
  s.add_dependency("tpool", ">= 0")
  s.add_dependency("wref", ">= 0.0.6")
end
