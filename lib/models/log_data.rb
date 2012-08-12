class Hayabusa::Models::Log_data < Knj::Datarow
  def self.force(d, id_hash)
    data_obj = d.ob.get_by(:Log_data, {"id_hash" => id_hash})
    
    if !data_obj
      data_obj = d.ob.add(:Log_data, {"id_hash" => id_hash})
    end
    
    return data_obj
  end
  
  def self.force_id(d, id_hash)
    data = d.db.query("SELECT * FROM Log_data WHERE id_hash = '#{d.db.esc(id_hash)}' LIMIT 1").fetch
    return data[:id].to_i if data
    return d.db.insert(:Log_data, {:id_hash => id_hash}, {:return_id => true}).to_i
  end
  
  def self.by_id_hash(d, id_hash)
    data = d.db.query("SELECT * FROM Log_data WHERE id_hash = '#{d.db.esc(id_hash)}' LIMIT 1").fetch
    return data[:id].to_i if data
    return false
  end
  
  def links(args = {})
    return ob.list(:Log_data_link, {"data" => self}.merge(args))
  end
end