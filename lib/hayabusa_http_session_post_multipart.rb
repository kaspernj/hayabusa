#This class parses and handels post-multipart requests.
class Hayabusa::Http_session::Post_multipart
  attr_reader :return
  
  def initialize(args)
    @args = args
    boundary_regexp = /\A--#{@args["boundary"]}(--)?#{@args["crlf"]}\z/
    @return = {}
    @data = nil
    @mode = nil
    @headers = {}
    @counts = {}
    
    @args["io"].each do |line|
      if boundary_regexp =~ line
        #Finish the data we were writing.
        self.finish_data if @data
        
        @data = ""
        @mode = "headers"
      elsif @mode == "headers"
        if match = line.match(/^(.+?):\s+(.+)#{@args["crlf"]}$/)
          @headers[match[1].to_s.downcase] = match[2]
        elsif line == @args["crlf"]
          @mode = "body"
        else
          raise "Could not match header from: '#{line}'."
        end
      elsif @mode == "body"
        @data << line
      else
        raise "Invalid mode: '#{@mode}'."
      end
    end
    
    self.finish_data if @data and @data.to_s.length > 0
    
    @data = nil
    @headers = nil
    @mode = nil
    @args = nil
  end
  
  #Add the current treated data to the return-hash.
  def finish_data
    @data.chop!
    name = nil
    
    disp = @headers["content-disposition"]
    raise "No 'content-disposition' was given." if !disp
    
    
    #Figure out value-name in post-hash.
    match_name = disp.match(/name=\"(.+?)\"/)
    raise "Could not match name." if !match_name
    name = match_name[1]
    
    
    #Fix count with name if given as increamental [].
    if match = name.match(/^(.+)\[\]$/)
      if !@counts.key?(match[1])
        @counts[match[1]] = 0
      else
        @counts[match[1]] += 1
      end
      
      name = "#{match[1]}[#{@counts[match[1]]}]"
    end
    
    
    #Figure out actual filename.
    match_fname = disp.match(/filename=\"(.+?)\"/)
    
    if match_fname
      obj = Hayabusa::Http_session::Post_multipart::File_upload.new(
        "fname" => match_fname[1],
        "headers" => @headers,
        "data" => @data
      )
      @return[name] = obj
      @data = nil
      @headers = {}
      @mode = nil
    else
      @return[name] = @data
      @data = nil
      @headers = {}
      @mode = nil
    end
  end
end

#This is the actual returned object for fileuploads. It is able to do various user-friendly things like save the content to a given path, return the filename, returns the content to a string and more.
class Hayabusa::Http_session::Post_multipart::File_upload
  def initialize(args)
    @args = args
  end
  
  #Returns the size of the upload.
  def size
    return @args["data"].length
  end
  
  #Returns the size of the fileupload.
  def length
    return @args["data"].length
  end
  
  #Returns the filename given for the fileupload.
  def filename
    return @args["fname"]
  end
  
  #Returns the headers given for the fileupload. Type and more should be here.
  def headers
    return @args["headers"]
  end
  
  #Returns the content of the file-upload as a string.
  def to_s
    return @args["data"]
  end
  
  #Saves the content of the fileupload to a given path.
  def save_to(filepath)
    File.open(filepath, "w") do |fp|
      fp.write(self.to_s)
    end
  end
  
  #This methods prevents the object from being converted to JSON. This can make some serious bugs.
  def to_json(*args)
    raise "File_upload-objects should not be converted to json."
  end
end