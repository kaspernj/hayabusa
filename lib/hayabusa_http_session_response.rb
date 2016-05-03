require "time"

#This object writes headers, trailing headers, status headers and more for HTTP-sessions.
class Hayabusa::Http_session::Response
  attr_accessor :chunked, :cgroup, :nl, :status, :http_version, :headers, :headers_trailing, :headers_sent, :socket

  STATUS_CODES = {
    100 => "Continue",
    200 => "OK",
    201 => "Created",
    202 => "Accepted",
    204 => "No Content",
    205 => "Reset Content",
    206 => "Partial Content",
    301 => "Moved Permanently",
    302 => "Found",
    303 => "See Other",
    304 => "Not Modified",
    307 => "Temporary Redirect",
    400 => "Bad Request",
    401 => "Unauthorized",
    403 => "Forbidden",
    404 => "Not Found",
    408 => "Request Timeout",
    415 => "Unsupported media type",
    500 => "Internal Server Error"
  }
  NL = "\r\n"

  def initialize(args)
    @chunked = false
    @socket = args[:socket]
    @hb = args[:hb]
  end

  def reset(args)
    @status = 200
    @http_version = args[:http_version]
    @close = args[:close]
    @fileobj = nil
    @close = true if @http_version == "1.0"
    @trailers = []
    @skip_statuscode = true if args[:mode] == :cgi
    @session_cookie = args[:cookie]
    @headers_sent = false
    @headers_trailing = {}
    @mode = args[:mode]
    @cookies = []

    @headers = {
      "date" => ["Date", Time.now.httpdate]
    }

    if args[:mode] != :cgi and (!args.key?(:chunked) or args[:chunked])
      @chunked = true
    end
  end

  def header(key, val)
    lines = val.to_s.count("\n") + 1
    raise "Value contains more lines than 1 (#{lines})." if lines > 1

    if !@headers_sent
      @headers[key.to_s.downcase.strip] = [key, val]
    else
      raise "Headers already sent and given header was not in trailing headers: '#{key}'." if @trailers.index(key) == nil
      @headers_trailing[key.to_s.downcase.strip] = [key, val]
    end
  end

  # Returns the value of a header.
  def get_header_value(header)
    header_p = header.to_s.downcase.strip

    gothrough = [@headers, @headers_trailing]
    gothrough.each do |headers|
      headers.each do |key, val|
        return val[1] if header_p == key
      end
    end

    return nil
  end

  # Returns true if the given header-name is sat.
  def has_header?(header)
    header_p = header.to_s.downcase.strip
    return @headers.key?(header_p) || @headers_trailing.key?(header_p)
  end

  def cookie(cookie)
    @cookies << cookie
    @session_cookie[cookie["name"]] = cookie["value"]
  end

  def header_str
    if @http_version == "1.1" && @chunked
      self.header("Connection", "Keep-Alive")
      self.header("Transfer-Encoding", "chunked")
    elsif @http_version == "1.1" && get_header_value("content-length").to_i > 0
      self.header("Connection", "Keep-Alive")
    end

    self.header("Keep-Alive", "timeout=15, max=30") if self.get_header_value("connection") == "Keep-Alive"

    if @skip_statuscode
      res = ""
    else
      if @http_version == "1.0"
        res = "HTTP/1.0 #{@status}"
      else
        res = "HTTP/1.1 #{@status}"
      end

      code = STATUS_CODES[@status]
      res << " #{code}" if code
      res << NL
    end

    # The status header is used to make CGI or FCGI use the correct status-code.
    self.header("Status", "#{@status} #{STATUS_CODES[@status]}")

    @headers.each do |key, val|
      res << "#{val[0]}: #{val[1]}#{NL}"
    end

    if @http_version == "1.1"
      @trailers.each do |trailer|
        res << "Trailer: #{trailer}#{NL}"
      end
    end

    @cookies.each do |cookie|
      res << "Set-Cookie: #{Knj::Web.cookie_str(cookie)}#{NL}"
    end

    res << NL

    return res
  end

  def write
    # Write headers to socket.
    @socket.write(self.header_str)
    @headers_sent = true
    @cgroup.chunked = @chunked

    # Set the content-length on the content-group to enable write-lenght-validation.
    if self.has_header?("content-length")
      @cgroup.content_length = self.get_header_value("content-length").to_i
    else
      @cgroup.content_length = nil
    end

    if @chunked
      @cgroup.write_to_socket
      @socket.write("0#{NL}")

      @headers_trailing.each do |header_id_str, header|
        @socket.write("#{header[0]}: #{header[1]}#{NL}")
      end

      @socket.write(NL)
    else
      @cgroup.write_to_socket
    end

    # Validate that no more has been written than given in content-length, since that will corrupt the client.
    if self.has_header?("content-length")
      length = cgroup.length_written
      content_length = self.get_header_value("content-length").to_i
      raise "More written than given in content-length: #{length}, #{content_length}" if length != content_length
    end

    # Close socket if that should be done.
    if @close and @mode != :cgi
      @hb.log_puts("Hauabusa: Closing socket.")
      @socket.close
    end
  end
end