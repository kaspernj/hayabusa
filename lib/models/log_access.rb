class Hayabusa::Models::Log_access < Knj::Datarow
  def get
    return data_hash("get")
  end
  
  def post
    return data_hash("post")
  end
  
  def meta
    return data_hash("meta")
  end
  
  def cookie
    return data_hash("cookie")
  end
  
  def ips
    return data_array(self[:ip_data_id])
  end
  
  def data_array(data_id)
    sql = "
      SELECT
        value_value.value AS value
      
      FROM
        Log_data_link AS value_links,
        Log_data_value AS value_value
      
      WHERE
        value_links.data_id = '#{data_id}' AND
        value_value.id = value_links.value_id
      
      ORDER BY
        key_links.no
    "
    
    arr = []
    q_array = db.query(sql)
    while d_array = q_array.fetch
      arr << d_array[:value]
    end
    
    return arr
  end
  
  def data_hash(type)
    col_keys_id = "#{type}_keys_data_id".to_sym
    col_values_id = "#{type}_values_data_id".to_sym
    
    keys_id = self[col_keys_id]
    values_id = self[col_values_id]
    
    keys_data_obj = ob.get(:Log_data, keys_id)
    values_data_obj = ob.get(:Log_data, values_id)
    
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
    q_hash = db.query(sql)
    while d_hash = q_hash.fetch
      hash[d_hash[:key].to_s] = d_hash[:value]
    end
    
    return hash
  end
end