class Hayabusa::Models::Log_link < Hayabusa::Datarow
  has_one [
    {:class => :Log, :col => :log_id, :method => :log}
  ]

  def self.list(d, &block)
    if d.args["count"]
      sql = "SELECT COUNT(id) AS count FROM #{table} WHERE 1=1"
      count = true
      d.args.delete("count")
    else
      sql = "SELECT * FROM #{table} WHERE 1=1"
    end

    q_args = nil
    ret = self.list_helper(d)
    sql << ret[:sql_joins]

    d.args.each do |key, val|
      case key
        when "object_class"
          data_val = d.db.single(:Log_data_value, {"value" => val})
          return [] if !data_val #if this data-value cannot be found, nothing has been logged for the object. So just return empty array here and skip the rest.
          sql << " AND object_class_value_id = '#{d.db.esc(data_val[:id])}'"
        when :cloned_ubuf
          q_args = {:cloned_ubuf => true}
        else
          raise "Invalid key: #{key}."
      end
    end

    sql << ret[:sql_where]

    return d.db.query(sql).fetch[:count].to_i if count

    sql << ret[:sql_order]
    sql << ret[:sql_limit]

    return d.ob.list_bysql(:Log_link, sql, q_args, &block)
  end

  def self.add(d)
    if d.data.has_key?(:object)
      class_data_id = d.ob.static(:Log_data_value, :force, d.data[:object].class.name)
      d.data[:object_class_value_id] = class_data_id.id
      d.data[:object_id] = d.data[:object].id
      d.data.delete(:object)
    end

    log = d.ob.get(:Log, d.data[:log_id]) #throws exception if it doesnt exist.
  end

  def object(ob_use)
    begin
      class_name = ob.get(:Log_data_value, self[:object_class_value_id])[:value].split("::").last
      return ob_use.get(class_name, self[:object_id])
    rescue Errno::ENOENT
      return false
    end
  end

  def object_class
    return ob.get(:Log_data_value, self[:object_class_value_id])[:value]
  end
end