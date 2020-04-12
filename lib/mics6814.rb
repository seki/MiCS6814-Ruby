class MiCS6814
  ADDR_IS_SET = 0
  ADDR_FACTORY_ADC_NH3 = 2
  ADDR_FACTORY_ADC_CO = 4
  ADDR_FACTORY_ADC_NO2 = 6

  ADDR_USER_ADC_HN3 = 8 # FIXME HN3? NH3??
  ADDR_USER_ADC_CO = 10
  ADDR_USER_ADC_NO2 = 12

  CH_VALUE_NH3 = 1
  CH_VALUE_CO = 2
  CH_VALUE_NO2 = 3

  CMD_READ_EEPROM = 6

  CMD_CONTROL_LED = 10
  CMD_CONTROL_PWR = 11

  def initialize(addr=4)
    @addr = addr
    @i2c = MinI2C.new

    @eeprom = {}
    @gas = Hash.new(0)

    @version = eeprom(ADDR_IS_SET) == 1126 ? 2 : 1
    raise "V2 is required" unless @version == 2
  end
  attr_reader :version, :i2c

  def get_data(*data)
    @i2c.i2cget(@addr, *data, 2).unpack("n").first
  end

  def set_data(*data)
    @i2c.i2cset(@addr, *data)
  end

  def eeprom(kind)
    @eeprom[kind] ||= get_data(CMD_READ_EEPROM, kind)
  end

  def get_gas1(ch)
    it = get_data(ch)
    @gas[ch] = it if it > 0
    @gas[ch]
  end

  def get_gas
    led_on

    a0 = [ADDR_USER_ADC_HN3, ADDR_USER_ADC_CO, ADDR_USER_ADC_NO2].map {|addr|
      get_data(6, addr)
    }

    a0 = [ADDR_FACTORY_ADC_NH3, ADDR_FACTORY_ADC_CO, ADDR_FACTORY_ADC_NO2].map {|addr|
      get_data(6, addr)
    }

    an = [CH_VALUE_NH3, CH_VALUE_CO, CH_VALUE_NO2].map {|ch| get_gas1(ch)}

    ratio = a0.zip(an).map do |v0, vn|
      vn.to_f / v0.to_f * (1023.0 - v0) / (1023.0 - vn)
      # ratio0 = (float)An_0 / (float)A0_0 * (1023.0 - A0_0) / (1023.0 - An_0);
    end
    pp [a0, an, ratio]

    led_off

    result = {}
    result['CO'] = (ratio[1] ** -1.179) * 4.385
    result['NO2'] = (ratio[2] ** 1.007) / 6.855
    result['NH3'] = (ratio[0] ** -1.67) / 1.47
    result['C3H8'] = (ratio[0] ** -2.518) * 570.164
    result['C4H10'] = (ratio[0] ** -2.138) * 398.107
    result['CH4'] = (ratio[1] ** -4.363) * 630.957
    result['H2'] = (ratio[1] ** -1.8) * 0.73
    result['C2H5OH'] = (ratio[1] ** -1.552) * 1.622

    result
  end

  def led_on
    set_data(CMD_CONTROL_LED, 1)
  end

  def led_off
    set_data(CMD_CONTROL_LED, 0)
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
