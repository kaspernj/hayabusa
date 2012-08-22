# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{hayabusa}
  s.version = "0.0.5"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Kasper Johansen"]
  s.date = %q{2012-08-22}
  s.description = %q{A threadded web/app-server that focuses on threadding, shared ressources, speed and more.}
  s.email = %q{k@spernj.org}
  s.executables = ["check_running.rb", "hayabusa_benchmark.rb", "hayabusa_cgi.rb", "hayabusa_fcgi.fcgi", "hayabusa_fcgi.rb", "knjappserver_start.rb"]
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.rdoc"
  ]
  s.files = [
    ".document",
    ".rspec",
    "Gemfile",
    "Gemfile.lock",
    "LICENSE.txt",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "bin/check_running.rb",
    "bin/hayabusa_benchmark.rb",
    "bin/hayabusa_cgi.rb",
    "bin/hayabusa_fcgi.fcgi",
    "bin/hayabusa_fcgi.rb",
    "bin/knjappserver_start.rb",
    "conf/apache2_cgi_rhtml_conf.conf",
    "conf/apache2_fcgi_rhtml_conf.conf",
    "conf/apache2_hayabusa_conf.conf",
    "hayabusa.gemspec",
    "lib/hayabusa.rb",
    "lib/hayabusa_cgi_session.rb",
    "lib/hayabusa_cgi_tools.rb",
    "lib/hayabusa_custom_io.rb",
    "lib/hayabusa_database.rb",
    "lib/hayabusa_erb_handler.rb",
    "lib/hayabusa_ext/cleaner.rb",
    "lib/hayabusa_ext/cmdline.rb",
    "lib/hayabusa_ext/errors.rb",
    "lib/hayabusa_ext/logging.rb",
    "lib/hayabusa_ext/mailing.rb",
    "lib/hayabusa_ext/sessions.rb",
    "lib/hayabusa_ext/threadding.rb",
    "lib/hayabusa_ext/threadding_timeout.rb",
    "lib/hayabusa_ext/translations.rb",
    "lib/hayabusa_ext/web.rb",
    "lib/hayabusa_fcgi.rb",
    "lib/hayabusa_http_server.rb",
    "lib/hayabusa_http_session.rb",
    "lib/hayabusa_http_session_contentgroup.rb",
    "lib/hayabusa_http_session_page_environment.rb",
    "lib/hayabusa_http_session_post_multipart.rb",
    "lib/hayabusa_http_session_request.rb",
    "lib/hayabusa_http_session_response.rb",
    "lib/hayabusa_models.rb",
    "lib/kernel_ext/gettext_methods.rb",
    "lib/kernel_ext/magic_methods.rb",
    "lib/models/log.rb",
    "lib/models/log_access.rb",
    "lib/models/log_data.rb",
    "lib/models/log_data_link.rb",
    "lib/models/log_data_value.rb",
    "lib/models/log_link.rb",
    "lib/models/session.rb",
    "pages/benchmark.rhtml",
    "pages/benchmark_print.rhtml",
    "pages/benchmark_simple.rhtml",
    "pages/benchmark_threadded_content.rhtml",
    "pages/debug_database_connections.rhtml",
    "pages/debug_http_sessions.rhtml",
    "pages/debug_memory_usage.rhtml",
    "pages/error_notfound.rhtml",
    "pages/logs_latest.rhtml",
    "pages/logs_show.rhtml",
    "pages/spec.rhtml",
    "pages/spec_post.rhtml",
    "pages/spec_test_multiple_clients.rhtml",
    "pages/spec_thread_joins.rhtml",
    "pages/spec_threadded_content.rhtml",
    "pages/tests.rhtml",
    "spec/cgi_spec.rb",
    "spec/custom_urls_spec.rb",
    "spec/fcgi_multiple_processes_spec.rb",
    "spec/fcgi_spec.rb",
    "spec/hayabusa_spec.rb",
    "spec/spec_helper.rb",
    "tests/cgi_test/config_cgi.rb",
    "tests/cgi_test/threadded_content_test.rhtml",
    "tests/cgi_test/vars_get_test.rhtml",
    "tests/cgi_test/vars_header_test.rhtml",
    "tests/cgi_test/vars_post_test.rhtml",
    "tests/fcgi_test/config_fcgi.rb",
    "tests/fcgi_test/index.rhtml",
    "tests/fcgi_test/sleeper.rhtml",
    "tests/fcgi_test/threadded_content_test.rhtml",
    "tests/fcgi_test/vars_get_test.rhtml",
    "tests/fcgi_test/vars_header_test.rhtml",
    "tests/fcgi_test/vars_post_test.rhtml"
  ]
  s.homepage = %q{http://github.com/kaspernj/hayabusa}
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.6.2}
  s.summary = %q{A threadded web/app-server that supports stand-alone, CGI and FCGI-modes.}

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<knjrbfw>, [">= 0"])
      s.add_runtime_dependency(%q<erubis>, [">= 0"])
      s.add_runtime_dependency(%q<mail>, [">= 0"])
      s.add_runtime_dependency(%q<datet>, [">= 0"])
      s.add_runtime_dependency(%q<http2>, [">= 0"])
      s.add_runtime_dependency(%q<tpool>, [">= 0"])
      s.add_development_dependency(%q<json>, [">= 0"])
      s.add_development_dependency(%q<rspec>, ["~> 2.3.0"])
      s.add_development_dependency(%q<bundler>, [">= 1.0.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.6.3"])
      s.add_development_dependency(%q<sqlite3>, [">= 0"])
    else
      s.add_dependency(%q<knjrbfw>, [">= 0"])
      s.add_dependency(%q<erubis>, [">= 0"])
      s.add_dependency(%q<mail>, [">= 0"])
      s.add_dependency(%q<datet>, [">= 0"])
      s.add_dependency(%q<http2>, [">= 0"])
      s.add_dependency(%q<tpool>, [">= 0"])
      s.add_dependency(%q<json>, [">= 0"])
      s.add_dependency(%q<rspec>, ["~> 2.3.0"])
      s.add_dependency(%q<bundler>, [">= 1.0.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.6.3"])
      s.add_dependency(%q<sqlite3>, [">= 0"])
    end
  else
    s.add_dependency(%q<knjrbfw>, [">= 0"])
    s.add_dependency(%q<erubis>, [">= 0"])
    s.add_dependency(%q<mail>, [">= 0"])
    s.add_dependency(%q<datet>, [">= 0"])
    s.add_dependency(%q<http2>, [">= 0"])
    s.add_dependency(%q<tpool>, [">= 0"])
    s.add_dependency(%q<json>, [">= 0"])
    s.add_dependency(%q<rspec>, ["~> 2.3.0"])
    s.add_dependency(%q<bundler>, [">= 1.0.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.6.3"])
    s.add_dependency(%q<sqlite3>, [">= 0"])
  end
end

