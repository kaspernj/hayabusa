class Hayabusa::Models::Log < Knj::Datarow
  has_many [
    {:class => :Log_link, :col => :log_id, :method => :links, :depends => true, :autodelete => true}
  ]
  
  def self.list(d, &block)
    sql = "SELECT #{table}.* FROM #{table}"
    
    if d.args["object_lookup"]
      data_val = d.ob.get_by(:Log_data_value, {"value" => d.args["object_lookup"].class.name})
      return [] if !data_val #if this data-value cannot be found, nothing has been logged for the object. So just return empty array here and skip the rest.
      
      sql << "
        LEFT JOIN Log_link ON
          Log_link.log_id = #{table}.id AND
          Log_link.object_class_value_id = '#{d.db.esc(data_val.id)}' AND
          Log_link.object_id = '#{d.db.esc(d.args["object_lookup"].id)}'
      "
    end
    
    q_args = nil
    return_sql = false
    ret = self.list_helper(d)
    
    sql << ret[:sql_joins]
    sql << " WHERE 1=1"
    
    d.args.each do |key, val|
      case key
        when "object_lookup"
          sql << " AND Log_link.id IS NOT NULL"
        when "return_sql"
          return_sql = true
        when "tag"
          data_val = d.ob.get_by(:Log_data_value, {"value" => val})
          if !data_val
            sql << " AND false"
          else
            sql << " AND Log.tag_data_id = '#{d.db.esc(data_val.id)}'"
          end
        when :cloned_ubuf
          q_args = {:cloned_ubuf => true}
        else
          raise "Invalid key: #{key}."
        end
    end
    
    sql << ret[:sql_where]
    sql << ret[:sql_order]
    sql << ret[:sql_limit]
    
    return sql if return_sql
    
    return d.ob.list_bysql(:Log, sql, q_args, &block)
  end
  
  def self.add(d)
    d.data[:date_saved] = Time.now if !d.data.key?(:date_saved)
  end
  
  def text
    return ob.get(:Log_data_value, self[:text_value_id])[:value]
  end
  
  def comment
    return "" if self[:comment_data_id].to_i == 0
    log_data = ob.get(:Log_data_value, self[:comment_data_id])
    return "" if !log_data
    return log_data[:value]
  end
  
  def tag
    return "" if self[:tag_data_id].to_i == 0
    log_data = ob.get(:Log_data_value, self[:tag_data_id])
    return "" if !log_data
    return log_data[:value]
  end
  
  def get
    ob.args[:hayabusa].log_data_hash(self[:get_keys_data_id], self[:get_values_data_id])
  end
  
  def post
    ob.args[:hayabusa].log_data_hash(self[:post_keys_data_id], self[:post_values_data_id])
  end
  
  def cookie
    ob.args[:hayabusa].log_data_hash(self[:cookie_keys_data_id], self[:cookie_values_data_id])
  end
  
  def meta
    ob.args[:hayabusa].log_data_hash(self[:meta_keys_data_id], self[:meta_values_data_id])
  end
  
  def session
    ob.args[:hayabusa].log_data_hash(self[:session_keys_data_id], self[:session_values_data_id])
  end
  
  def ip
    meta_d = self.meta
    
    return meta_d[:HTTP_X_FORWARDED_FOR] if meta_d.has_key?(:HTTP_X_FORWARDED_FOR)
    return meta_d[:REMOTE_ADDR] if meta_d.has_key?(:REMOTE_ADDR)
    return "[no ip logged]"
  end
  
  def first_line
    lines = self.text.to_s.split("\n").first.to_s
  end
  
  def objects_html(ob_use)
    html = ""
    first = true
    
    self.links.each do |link|
      obj = link.object(ob_use)
      
      html << ", " if !first
      first = false if first
      
      if obj.respond_to?(:html)
        html << obj.html
      else
        html << "#{obj.class.name}{#{obj.id}}"
      end
    end
    
    return html
  end
end