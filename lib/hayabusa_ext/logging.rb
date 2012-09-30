class Hayabusa
  def initialize_logging
    @logs_access_pending = []
    @logs_mutex = Mutex.new
    
    if @config[:logging] and @config[:logging][:access_db]
      self.timeout(:time => 30, &self.method(:flush_access_log))
    end
  end
  
  #Writes all queued access-logs to the database.
  def flush_access_log
    return nil if @logs_access_pending.empty?
    
    @logs_mutex.synchronize do
      ins_arr = @logs_access_pending
      @logs_access_pending = []
      inserts = []
      inserts_links = []
      
      ins_arr.each do |ins|
        gothrough = [{
          :col => :get_keys_data_id,
          :hash => ins[:get],
          :type => :keys
        },{
          :col => :get_values_data_id,
          :hash => ins[:get],
          :type => :values
        },{
          :col => :post_keys_data_id,
          :hash => ins[:post],
          :type => :keys
        },{
          :col => :post_values_data_id,
          :hash => ins[:post],
          :type => :values
        },{
          :col => :cookie_keys_data_id,
          :hash => ins[:cookie],
          :type => :keys
        },{
          :col => :cookie_values_data_id,
          :hash => ins[:cookie],
          :type => :values
        },{
          :col => :meta_keys_data_id,
          :hash => ins[:meta],
          :type => :keys
        },{
          :col => :meta_values_data_id,
          :hash => ins[:meta],
          :type => :values
        }]
        ins_hash = {
          :session_id => ins[:session_id],
          :date_request => ins[:date_request]
        }
        
        gothrough.each do |data|
          if data[:type] == :keys
            hash = Knj::ArrayExt.hash_keys_hash(data[:hash])
          else
            hash = Knj::ArrayExt.hash_values_hash(data[:hash])
          end
          
          data_id = @ob.static(:Log_data, :by_id_hash, hash)
          if !data_id
            data_id = @db.insert(:Log_data, {"id_hash" => hash}, {:return_id => true})
            
            link_count = 0
            data[:hash].keys.sort.each do |key|
              if data[:type] == :keys
                ins_data = "#{key.to_s}"
              else
                ins_data = "#{data[:hash][key]}"
              end
              
              ins_data = ins_data.force_encoding("UTF-8") if ins_data.respond_to?(:force_encoding)
              data_value_id = @ob.static(:Log_data_value, :force_id, ins_data)
              inserts_links << {:no => link_count, :data_id => data_id, :value_id => data_value_id}
              link_count += 1
            end
          end
          
          ins_hash[data[:col]] = data_id
        end
        
        hash = Knj::ArrayExt.array_hash(ins[:ips])
        data_id = @ob.static(:Log_data, :by_id_hash, hash)
        
        if !data_id
          data_id = @db.insert(:Log_data, {"id_hash" => hash}, {:return_id => true})
          
          link_count = 0
          ins[:ips].each do |ip|
            data_value_id = @ob.static(:Log_data_value, :force_id, ip)
            inserts_links << {:no => link_count, :data_id => data_id, :value_id => data_value_id}
            link_count += 1
          end
        end
        
        ins_hash[:ip_data_id] = data_id
        inserts << ins_hash
      end
      
      @db.insert_multi(:Log_access, inserts)
      @db.insert_multi(:Log_data_link, inserts_links)
      @ob.unset_class([:Log_access, :Log_data, :Log_data_link, :Log_data_value])
    end
  end
  
  #Converts fileuploads into strings so logging wont be crazy big.
  def log_hash_safe(hash)
    hash_obj = {}
    hash.each do |key, val|
      if val.is_a?(Hayabusa::Http_session::Post_multipart::File_upload)
        hash_obj[key] = "<Fileupload>"
      elsif val.is_a?(Hash)
        hash_obj[key] = self.log_hash_safe(val)
      else
        hash_obj[key] = val
      end
    end
    
    return hash_obj
  end
  
  #Handles the hashes that should be logged.
  def log_hash_ins(hash_obj)
    #Sort out fileuploads - it would simply bee too big to log this.
    hash_obj = self.log_hash_safe(hash_obj)
    
    inserts_links = []
    ret = {}
    [:keys, :values].each do |type|
      if type == :keys
        hash = Knj::ArrayExt.hash_keys_hash(hash_obj)
      else
        hash = Knj::ArrayExt.hash_values_hash(hash_obj)
      end
      
      data_id = @db.single(:Log_data, {"id_hash" => hash})
      data_id = data_id[:id] if data_id
      
      if !data_id
        data_id = @db.insert(:Log_data, {"id_hash" => hash}, {:return_id => true})
        
        link_count = 0
        hash_obj.keys.sort.each do |key|
          if type == :keys
            ins_data = "#{key.to_s}"
          else
            ins_data = "#{hash_obj[key].to_s}"
          end
          
          ins_data = ins_data.force_encoding("UTF-8") if ins_data.respond_to?(:force_encoding)
          data_value_id = @ob.static(:Log_data_value, :force_id, ins_data)
          inserts_links << {:no => link_count, :data_id => data_id, :value_id => data_value_id}
          link_count += 1
        end
      end
      
      if type == :keys
        ret[:keys_data_id] = data_id
      else
        ret[:values_data_id] = data_id
      end
    end
    
    @db.insert_multi(:Log_data_link, inserts_links)
    
    return ret
  end
  
  def log_data_hash(keys_id, values_id)
    begin
      keys_data_obj = @ob.get(:Log_data, keys_id)
      values_data_obj = @ob.get(:Log_data, values_id)
    rescue Errno::ENOENT
      return {}
    end
    
    sql = "
      SELECT
        key_value.value AS `key`,
        value_value.value AS value
      
      FROM
        Log_data_link AS key_links,
        Log_data_link AS value_links,
        Log_data_value AS key_value,
        Log_data_value AS value_value
      
      WHERE
        key_links.data_id = '#{keys_id}' AND
        value_links.data_id = '#{values_id}' AND
        key_links.no = value_links.no AND
        key_value.id = key_links.value_id AND
        value_value.id = value_links.value_id
      
      ORDER BY
        key_links.no
    "
    
    hash = {}
    db.q(sql) do |d_hash|
      hash[d_hash[:key].to_sym] = d_hash[:value]
    end
    
    return hash
  end
  
  #Writes a custom log to the database.
  def log(msg, objs, args = {})
    #This can come in handy if migrating logs to appserver-database.
    if args[:date_saved]
      date_saved = args[:date_saved]
    else
      date_saved = Time.now
    end
    
    objs = [objs] if !objs.is_a?(Array)
    
    @logs_mutex.synchronize do
      log_value_id = @ob.static(:Log_data_value, :force_id, msg)
      
      ins_data = {
        :date_saved => date_saved,
        :text_value_id => log_value_id
      }
      
      get_hash = log_hash_ins(_get) if _get
      if get_hash
        ins_data[:get_keys_data_id] = get_hash[:keys_data_id]
        ins_data[:get_values_data_id] = get_hash[:values_data_id]
      end
      
      post_hash = log_hash_ins(_post) if _post
      if post_hash
        ins_data[:post_keys_data_id] = post_hash[:keys_data_id]
        ins_data[:post_values_data_id] = post_hash[:values_data_id]
      end
      
      cookie_hash = log_hash_ins(_cookie) if _cookie
      if cookie_hash
        ins_data[:post_keys_data_id] = cookie_hash[:keys_data_id]
        ins_data[:post_values_data_id] = cookie_hash[:values_data_id]
      end
      
      meta_hash = log_hash_ins(_meta) if _meta
      if cookie_hash
        ins_data[:meta_keys_data_id] = meta_hash[:keys_data_id]
        ins_data[:meta_values_data_id] = meta_hash[:values_data_id]
      end
      
      session_hash = log_hash_ins(_session) if _session
      if session_hash
        ins_data[:session_keys_data_id] = session_hash[:keys_data_id]
        ins_data[:session_values_data_id] = session_hash[:values_data_id]
      end
      
      if args[:tag]
        tag_value_id = @ob.static(:Log_data_value, :force_id, args[:tag])
        ins_data[:tag_data_id] = tag_value_id
      end
      
      if args[:comment]
        comment_value_id = @ob.static(:Log_data_value, :force_id, args[:comment])
        ins_data[:comment_data_id] = comment_value_id
      end
      
      log_id = @db.insert(:Log, ins_data, {:return_id => true})
      
      log_links = []
      objs.each do |obj|
        class_data_id = @ob.static(:Log_data_value, :force_id, obj.class.name)
        
        log_links << {
          :object_class_value_id => class_data_id,
          :object_id => obj.id,
          :log_id => log_id
        }
      end
      
      @db.insert_multi(:Log_link, log_links)
    end
  end
  
  #Deletes all logs for an object.
  def logs_delete(obj)
    @db.q_buffer do |db_buffer|
      buffer_hash = {:db_buffer => db_buffer}
      
      @ob.list(:Log_link, {"object_class" => obj.class.name, "object_id" => obj.id}) do |log_link|
        log = log_link.log
        @ob.delete(log_link, buffer_hash)
        @ob.delete(log, buffer_hash) if log and log.links("count" => true) <= 0
      end
    end
  end
  
  #Returns the HTML for a table with logs from a given object.
  def logs_table(obj, args = {})
    if args[:out]
      html = args[:out]
    else
      html = $stdout
    end
    
    html = ""
    
    html << "<table class=\"list hayabusa_log_table\">"
    html << "<thead>"
    html << "<tr>"
    html << "<th>ID</th>"
    html << "<th>Message</th>"
    html << "<th style=\"width: 130px;\">Date &amp; time</th>"
    html << "<th>Tag</th>"
    html << "<th>Objects</th>" if args[:ob_use]
    html << "<th>IP</th>" if args[:show_ip]
    html << "</tr>"
    html << "</thead>"
    html << "<tbody>"
    
    count = 0
    @ob.list(:Log_link, {"object_class" => obj.class.name, "object_id" => obj.id, "limit" => 500, "orderby" => [["id", "desc"]]}) do |link|
      count += 1
      log = link.log
      
      msg_lines = log.text.split("\n")
      first_line = msg_lines[0].to_s
      
      classes = ["hayabusa_log", "hayabusa_log_#{log.id}"]
      classes << "hayabusa_log_multiple_lines" if msg_lines.length > 1
      
      html << "<tr class=\"#{classes.join(" ")}\">"
      html << "<td>#{log.id}</td>"
      html << "<td>#{first_line.html}</td>"
      html << "<td>#{log.date_saved_str}</td>"
      html << "<td>#{log.tag.html}</td>"
      
      if args[:ob_use]
        begin
          html << "<td>#{log.objects_html(args[:ob_use])}</td>"
        rescue => e
          html << "<td>#{e.message.html}</td>"
        end
      end
      
      html << "<td>#{log.ip}</td>" if args[:show_ip]
      html << "</tr>"
    end
    
    if count <= 0
      html << "<tr>"
      html << "<td colspan=\"2\" class=\"error\">No logs were found for that object.</td>"
      html << "</tr>"
    end
    
    html << "</tbody>"
    html << "</table>"
    
    return nil
  end
  
  #Removes all logs for objects that have been deleted.
  #===Examples
  #Remember to pass Knj::Objects-object handler to the method.
  # appsrv.logs_delete_dead(:ob => ob, :debug => false)
  def logs_delete_dead(args)
    raise "No :ob-argument given." if !args[:ob]
    
    @db.q_buffer do |db_buffer|
      self.log_puts("Starting to look for dead log-links.") if @debug or args[:debug]
      @ob.list(:Log_link, :cloned_ubuf => true) do |log_link|
        classname = log_link.object_class.to_s.split("::").last
        obj_exists = args[:ob].exists?(classname, log_link[:object_id])
        next if obj_exists
        
        log = log_link.log
        
        self.log_puts("Deleting log-link #{log_link.id} for #{classname}(#{log_link[:object_id]}).") if @debug or args[:debug]
        @ob.delete(log_link, :db_buffer => db_buffer)
        
        links_count = log.links("count" => true)
        
        if links_count <= 0
          self.log_puts("Deleting log #{log.id} because it has no more links.") if @debug or args[:debug]
          @ob.delete(log, :db_buffer => db_buffer)
        end
      end
      
      self.log_puts("Starting to look for logs with no links.") if @debug or args[:debug]
      @ob.list(:Log, {
        [:Log_link, "id"] => {:type => :sqlval, :val => :null},
        :cloned_ubuf => true
      }) do |log|
        self.log_puts("Deleting log #{log.id} because it has no links: '#{log.text}'.") if @debug or args[:debug]
        @ob.delete(log, :db_buffer => db_buffer)
      end
    end
  end
end