require "tempfile"

#This class parses and handels post-multipart requests.
class Hayabusa::Http_session::Post_multipart
  #This hash contains all the data read from the post-request.
  attr_reader :return
  
  def initialize(args)
    @args = args
    crlf = args[:crlf]
    crlf_len = crlf.length
    
    boundary_regexp = /\A--#{Regexp.escape(@args[:boundary])}(--)?(\r\n|\n|$)\z/
    @return = {}
    @data = nil
    @mode = nil
    @clength = 0
    @headers = {}
    @counts = {}
    str_crlf = nil
    
    @args[:io].each do |line|
      begin
        boundary_match = line.match(boundary_regexp)
      rescue ArgumentError
        #Happens when "invalid byte sequence in UTF-8" - the boundary-line will be UTF-8-valid and match the 'boundary_regexp'.
        boundary_match = false
      end
      
      if boundary_match
        #Finish the data we were writing.
        self.finish_data if @data
        
        @data_written = 0
        @clength = nil
        @name = nil
        @mode = "headers"
        str_crlf = nil
      elsif @mode == "headers"
        if match = line.match(/^(.+?):\s+(.+)#{crlf}$/)
          key = match[1].to_s.downcase
          val = match[2]
          
          @headers[key] = val
          
          if key == "content-length"
            @clength = val.to_i
          elsif key == "content-disposition"
            #Figure out value-name in post-hash.
            match_name = val.match(/name=\"(.+?)\"/)
            raise "Could not match name." if !match_name
            @name = match_name[1]
            
            #Fix count with name if given as increamental [].
            if match = @name.match(/^(.+)\[\]$/)
              if !@counts.key?(match[1])
                @counts[match[1]] = 0
              else
                @counts[match[1]] += 1
              end
              
              @name = "#{match[1]}[#{@counts[match[1]]}]"
            end
            
            #Figure out actual filename.
            if match_fname = val.match(/filename=\"(.+?)\"/)
              @fname = match_fname[1]
              @data = Tempfile.new("hayabusa_http_session_post_multipart")
            else
              @data = ""
            end
          end
        elsif line == crlf
          @mode = "body"
        else
          raise "Could not match header from: '#{line}'."
        end
      elsif @mode == "body"
        if line[-crlf_len, crlf_len] == crlf
          str = "#{str_crlf}#{line[0, line.length - crlf_len]}"
          str_crlf = crlf
        else
          str = "#{str_crlf}#{line}"
          str_crlf = nil
        end
        
        @data_written += str.bytesize
        @data << str
        
        self.finish_data if @clength and @data_written >= @clength
      elsif !@mode and (line == crlf or line == "\n" or line == "\r\n")
        #ignore.
      else
        raise "Invalid mode: '#{@mode}' (#{@mode.class.name}) for line: '#{line}' for total post-string:\n#{@args[:io].string}"
      end
    end
    
    self.finish_data if @data
    
    @data = nil
    @headers = nil
    @mode = nil
    @args = nil
  end
  
  #Add the current treated data to the return-hash.
  def finish_data
    if @headers.empty? and @data_written == 0
      @data.close(true) if @data.is_a?(Tempfile)
      
      self.reset_data
      return nil
    end
    
    @data.close(false) if @data.is_a?(Tempfile)
    raise "No 'content-disposition' was given (#{@headers}) (#{@data})." if !@name
    
    if @fname
      obj = Hayabusa::Http_session::Post_multipart::File_upload.new(
        :fname => @fname,
        :headers => @headers,
        :data => @data
      )
      @return[@name] = obj
    else
      @return[@name] = @data
    end
    
    self.reset_data
  end
  
  def reset_data
    @data = nil
    @name = nil
    @fname = nil
    @headers = {}
    @mode = nil
    @clength = 0
  end
end

#This is the actual returned object for fileuploads. It is able to do various user-friendly things like save the content to a given path, return the filename, returns the content to a string and more.
class Hayabusa::Http_session::Post_multipart::File_upload
  def initialize(args)
    @args = args
  end
  
  #Returns the size of the upload.
  def size
    return @args[:data].length
  end
  
  #Returns the size of the fileupload.
  def length
    return @args[:data].length
  end
  
  #Returns the filename given for the fileupload.
  def filename
    return @args[:fname]
  end
  
  #Returns the headers given for the fileupload. Type and more should be here.
  def headers
    return @args[:headers]
  end
  
  #Returns the content of the file-upload as a string.
  def to_s
    if @args[:data].is_a?(StringIO)
      return @args[:data].string
    else
      return File.read(@args[:data].path)
    end
  end
  
  #Returns an IO to read from the upload wherever it is a temporary file or a string.
  def io(&blk)
    if @args[:data].is_a?(StringIO)
      return @args[:data]
    else
      return File.open(@args[:data].path, "r", &blk)
    end
  end
  
  #Saves the content of the fileupload to a given path.
  def save_to(filepath)
    File.open(filepath, "w") do |fp|
      if @args[:data].is_a?(StringIO)
        fp.write(@args[:data].string)
      else
        #Stream output to avoid using too much memory.
        self.io do |fp_read|
          fp_read.lines do |line|
            fp.write(line)
          end
        end
      end
    end
  end
  
  #This methods prevents the object from being converted to JSON. This can make some serious bugs.
  def to_json(*args)
    raise "File_upload-objects should not be converted to json."
  end
end