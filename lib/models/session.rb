class Hayabusa::Models::Session < Knj::Datarow
  attr_reader :edata
  attr_accessor :sess_data
  
  def initialize(*args, &block)
    @edata = {}
    super(*args, &block)
    
    if self[:sess_data].to_s.length > 0
      begin
        @sess_data = Marshal.load(Base64.decode64(self[:sess_data]))
      rescue ArgumentError
        @sess_data = {}
      end
    else
      @sess_data = {}
    end
  end
  
  def self.add(d)
    d.data[:date_added] = Time.now if !d.data[:date_added]
    d.data[:date_lastused] = Time.now if !d.data[:date_lastused]
  end
  
  def flush
    flush_data = Base64.encode64(Marshal.dump(@sess_data))
    
    if self[:sess_data] != flush_data
      self.update(
        :sess_data => flush_data,
        :date_lastused => Time.now
      )
    end
  end
end