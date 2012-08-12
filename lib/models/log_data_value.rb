class Hayabusa::Models::Log_data_value < Knj::Datarow
  def self.force(d, value)
    value_obj = d.ob.get_by(:Log_data_value, {
      "value" => value.to_s
    })
    
    if !value_obj
      value_obj = d.ob.add(:Log_data_value, {"value" => value})
    end
    
    return value_obj
  end
  
  def self.force_id(d, value)
    d.db.select(:Log_data_value, {"value" => value}) do |d_val|
      return d_val[:id].to_i if d_val[:value].to_s == value.to_s #MySQL doesnt take upper/lower-case into consideration because value is a text-column... lame! - knj
    end
    
    return d.db.insert(:Log_data_value, {:value => value}, {:return_id => true}).to_i
  end
end