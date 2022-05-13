# Hayabusa Webserver

This is a multithreadded webserver that runs under Ruby 1.9.2 or JRuby. It runs under one single process and is able to handle multiple simultanious HTTP requests with thread-safety.

It uses ERubis to parse .rhtml files and caches the bytecode for Ruby-files.


## Contributing to hayabusa

* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it
* Fork the project
* Start a feature/bugfix branch
* Commit and push until you are happy with your contribution
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2011 Kasper Johansen. See LICENSE.txt for
further details.

## Installing
```ruby
gem install hayabusa
```

## Usage

### Basic example

Create a file called "start.rb":
```ruby
require "rubygems"
require "hayabusa"

require "knjrbfw"
require "sqlite3"

appsrv = Hayabusa.new(
  port: 10080,
  doc_root: "#{File.dirname(__FILE__)}/doc_root",
  db: Baza::Db.new(
    type: "sqlite3",
    path: "#{File.dirname(__FILE__)}/test.sqlite3"
  )
)
appsrv.update_db #creates missing tables, columns, indexes or other stuff it needs.
appsrv.start
appsrv.join
```


Place a file called "index.rhtml" with the start-script and write something like:
```erb
<%
  print "Hello world."
%>
```

Then go to your browser and type "localhost:10080".


### How to send a header
```erb
<%
  _hb.header("SomeHeader", "SomeValue")
%>
```

If you have trouble, because the server already began to send the content while the page was not fully generated, then you can increase the size for when it should begin sending content like this:
```ruby
appsrv = Hayabusa.new(
  ...
  send_size: 4096
  ...
)
```

Or you can do it for just one page dynamically (this should be done VERY early - like before the first lines gets printed out):
```erb
<%
  _hb.headers_send_size = 4096
%>
```

You can also test if the headers are sent for your HTTP-session or not like this:
```erb
<%
  if _hb.headers_sent?
    print "The headers are sent!"
  else
    print "The headers are not sent yet - we can still add headers!"
  end
%>
```

### How to send set a cookie
```erb
<%
  _hb.cookie(
    "name" => "MyCookie",
    "value" => "SomeValue",
    "expires" => Time.new + 3600,
    "path" => "/"
  )
%>
```

### How to do threadded content
```erb
<%
  _hb.threadded_content do
    sleep 4
    print "Test 1<br />"
  end

  _hb.threadded_content do
    sleep 1
    print "Test 2<br />"
  end

  _hb.threadded_content do
    sleep 3
    print "Test 3<br />"
  end
%>
```

It should print in the right order, even though "Test 1" will finish as the last thread:
```
Test 1
Test 2
Test 3
```

### How to access request data
```erb
<%
  puts _get
  puts _post
  puts _meta
  puts _cookie
  puts _session
  puts _session_hash
%>
```

### How to set session variables:
```ruby
_session[:logged_in] = true
```

### How to set other objects that cant be marshalled on sessions (variables will die after restart):
```ruby
_session_hash[:mythread] = Thread.new do
  do_some_stuff
end
```


### How to access the database
```erb
<%
  _db.q("SELECT * FROM Session") do |data|
    puts data
  end
%>
```

### How to create a thread with database access that runs in background via the threadpool
```erb
<%
  _hb.thread do
    sleep 2
    print "Trala!\n"  #will be outputted to the command line, since the thread is being executed in the background and the http-request wont depend on it!
  end
%>
```

### How to do execute something every 10 seconds.
```erb
<%
  _hb.timeout(:time => 10) do
    print "This will be printed to the command line every 10 secs.\n"
  end
%>
```

### How to send a mail

1. Be sure to start the appserver with SMTP arguments:
```ruby
appsrv = Hayabusa.new(
  ...
  smtp_paras: {
    "smtp_host" => "hostname",
    "smtp_port" => 465,
    "smtp_user" => "username,
    "smtp_passwd" => "password",
    "ssl" => true
  }
  ...
)
```

2. Do something like this:
```erb
<%
  _hb.mail(
    :to => "friends@email.com",
    :subject => "The subject",
    :html => "The HTML content.",
    :from => "your@email.com"
  )
%>
```

You can also make the appserver send you an email every time an error occurrs:
```erb
<%
  appsrv = Hayabusa.new(
    ...
    :error_report_emails => ["your@email.com", "another@email.com"],
    :error_report_from => "robot@domain.com"
    ...
  )
%>
```

### How to use Gettext / Locales

1. Make folders and po-files so you have something like: "locales/en_GB/LC_MESSAGES/default.po".

2. Start the appserver with the following arguments:
```ruby
appsrv = Hayabusa.new(
  ...
  locales_root: "#{File.dirname(__FILE__)}/../locales",
  locales_gettext_funcs: true,
  locale_default: "da_DK",
  ...
)
```

3. Use gettext like your normally would:
```erb
<%
  print _("Hello world.")
%>
```

4. Dont do "require 'gettext'" or anything like this - the appserver does it all for you!


=== How to use multithreadded MySQL without mutex'ing around it.

1. Install the 'mysql2' gem.
```ruby
gem install mysql2
```

2. Start the appserver with the following arguments:
```ruby
appsrv = Hayabusa.new(
  ...
  db: {
    type: "mysql",
    subtype: "mysql2",
    host: "localhost",
    user: "username",
    pass: "password",
    db: "database",
    return_keys: "symbols",
    threadsafe: true,
    encoding: "utf8",
    query_args: {cast: false}
  }
  ...
)


### How to make a cron-script that checks if my app is running through the appserver.

1. Be sure to start the appserver with a title:
```ruby
appsrv = Hayabusa.new(
  ...
  title: "MyApp"
  ...
)
```

2. Add this command to your cron-config:
```shell
/bin/bash -l -c "ruby ~/.rvm/gems/ruby-1.9.2-head/gems/hayabusa-*/bin/check_running.rb --title=MyApp --forking=1 --command=\"ruby /path/to/app/start_script.rb\""
```

### How to restart the appserver from Ruby or restart it based on memory usage.

1. Be sure to start the appserver with a restart-command:
```ruby
appsrv = Hayabusa.new(
  ...
  restart_cmd: "/usr/bin/ruby1.9.1 /path/to/app/start.rb"
  ...
)
```

2. You can also make it restart itself based on memory usage:
```ruby
appsrv = Hayabusa.new(
  ...
  restart_when_used_memory: 384
  ...
)
```

3. You can restart it dynamically (or test that it is able to restart itself with your given arguments) by doing something like this:
```erb
<%
  _hb.should_restart = true
%>
```

When it restarts it will wait for a window with no running HTTP requests before restarting.


### How to use helper methods.

1. This will show a message by using javascript in execute history.back(-1) afterwards.
```ruby
_hb.alert("You can only view this page if you are logged in.").back if !logged_in
```

2. This will show the error message and execute history.back(-1) afterwards.
```ruby
_hb.on_error_go_back do
  raise "test"
end
```

3. This will redirect the user and not execute anything after it:
```ruby
_hb.redirect("?show=frontpage")
```

4. We also add the method "html" to the String-class so escaping it is painless:
```ruby
print "<b>Will this be bold?</b>".html
```

5. This is how you can escape SQL-stuff:
```ruby
data = _db.query("SELECT * FROM Session WHERE id ='#{_db.esc(some_var)}'").fetch
```

6. Print strings using short-tag:
```erb
<div>
  My name is <%=name_var%>.
</div>
  ```
