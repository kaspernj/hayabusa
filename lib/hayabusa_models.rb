class Hayabusa::Models
  #Autoloader for subclasses.
  def self.const_missing(name)
    require "#{File.dirname(__FILE__)}/models/#{name.to_s.downcase}.rb"
    raise "Still not defined: '#{name}'." if !Hayabusa::Models.const_defined?(name)
    return Hayabusa::Models.const_get(name)
  end
end