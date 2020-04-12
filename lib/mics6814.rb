class MiCS6814
  def initialize(addr=4)
    @addr = addr
    @i2c = MinI2C.new

    @eeprom = {}
    @gas = Hash.new(0)

    @version = eeprom(kind) == 1126 ? 2 : 1
  end
  attr_reader :version, :i2c

  def get_data(*data)
    @i2c.i2cget(@addr, *data, 2).unpack("n").first
  end

  def set_data(*data)
    @i2c.i2cset(@addr, *data)
  end

  def eeprom(kind)
    @eeprom[kind] ||= get_data(6, kind)
  end

  def led_on
    set_data(10, 1)
  end

  def led_off
    set_data(10, 0)
  end

  class MinI2C
    I2C_SLAVE       = 0x0703
    I2C_SLAVE_FORCE = 0x0706
  
    class I2CIOError < RuntimeError; end
  
    def initialize(path=nil, force=false)
      if path.nil?
        path = Dir.glob("/dev/i2c-*").sort.last
      end
  
      unless File.exist?(path)
        raise I2CIOError, "/dev/i2c-0 is required"
      end
  
      @path = path
      @slave_command = force ? I2C_SLAVE_FORCE : I2C_SLAVE
    end
  
    def i2cget(address, *param, length)
      i2c = File.open(@path, "r+")
      i2c.ioctl(@slave_command, address)
      i2c.syswrite(param.pack("C*")) unless param.empty?
      ret = i2c.sysread(length)
      i2c.close
      ret
    rescue Errno::EIO => e
      raise I2CIOError, e.message
    end
  
    def i2cset(address, *data)
      i2c = File.open(@path, "r+")
      i2c.ioctl(@slave_command, address)
      i2c.syswrite(data.pack("C*"))
      i2c.close
    rescue Errno::EIO => e
      raise I2CIOError, e.message
    end
  end  
end
