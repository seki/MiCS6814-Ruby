
=begin
import from jvalrog/bme280.rb
https://gist.github.com/jvalrog/c515302f150327caebf0352989ab1df8
=end

class BME280
  R_DIG_T1 = 0x88
	R_DIG_P1 = 0x8E
	R_DIG_H1 = 0xA1
	R_DIG_H2 = 0xE1
	R_PRESS_MSB = 0xF7
	R_CTRL_HUM = 0xF2
  R_CTRL_MEAS = 0xF4
  
  def initialize(addr=0x77)
    @addr = addr
    @i2c = MinI2C.new
    setup
  end
  attr_reader :i2c

  def setup
    @i2c.i2cset(@addr, R_CTRL_HUM, 0x05)
		@i2c.i2cset(@addr, R_CTRL_MEAS, 0xb7)
  end

	def patch_adc_data(adc_data)
		bytes = adc_data.bytes
		bytes.insert(3, 0)
		bytes.insert(7, 0)
		bytes.pack("C*")
	end

	def adc_read
		data = @i2c.i2cget(@addr, R_PRESS_MSB, 8)
		data = patch_adc_data(data)
		p, t, h = data.unpack("L>L>S>")
		
		{p: p >> 12, t: t >> 12, h: h}
  end

  def patch_h_data(h_data)
		bytes = h_data.bytes
		e5 = bytes[5]
		h4 = (bytes[4] << 4) + (e5 & 0x0f)
		bytes[4] = h4 & 0xff
		bytes[5] = h4 >> 8
		h5 = (e5 >> 4) + (bytes[6] << 4)
		bytes.insert(6, h5 & 0xff)
		bytes[7] = h5 >> 8
		bytes.pack("C*")
	end
  
  def calib
		return @cdata if defined?(@cdata)
		
		t_data = @i2c.i2cget(@addr, R_DIG_T1, 6)
		p_data = @i2c.i2cget(@addr, R_DIG_P1, 18)
		h_data = ""
		h_data << @i2c.i2cget(@addr, R_DIG_H1, 1)
		h_data << @i2c.i2cget(@addr, R_DIG_H2, 7)
		h_data = patch_h_data(h_data)
		
		@cdata = {t: t_data.unpack("S<s<2"), p: p_data.unpack("S<s<8"), h: h_data.unpack("Cs<Cs<2c")}
	end

  def update
		adc = adc_read
		t_fine = calc_t_fine(adc[:t])
    
    sensors = {}
		sensors[:t] = compensate_t(t_fine)
		sensors[:p] = compensate_p(adc[:p], t_fine)
    sensors[:h] = compensate_h(adc[:h], t_fine)
    sensors
  end
  
	def calc_t_fine(adc_t)
		var1 = (adc_t / 16384.0 - calib[:t][0] / 1024.0) * calib[:t][1]
		var2 = ((adc_t / 131072.0 - calib[:t][0] / 8192) ** 2) * calib[:t][2]
		var1 + var2
	end

  def compensate_t(t_fine)
		t_fine / 5120.0
	end
	
	def compensate_p(adc_p, t_fine)
		var1 = t_fine / 2.0 - 64000.0
		var2 = (var1 ** 2) * calib[:p][5] / 32768.0
		var2 = var2 + var1 * calib[:p][4] * 2.0
		var2 = var2 / 4.0 + calib[:p][3] * 65536.0
		var1 = (calib[:p][2] * (var1 ** 2) / 524288.0 + calib[:p][1] * var1) / 524288.0
		var1 = (1.0 + var1 / 32768.0) * calib[:p][0]
		
		return 0 if var1 == 0
		
		p = 1048576.0 - adc_p
		p = (p - var2 / 4096.0) * 6250.0 / var1
		var1 = calib[:p][8] * (p ** 2) / 2147483648.0
		var2 = p * calib[:p][7] / 32768.0
		(p + (var1 + var2 + calib[:p][6]) / 16.0) / 100.0
	end
  
  def compensate_h(adc_h, t_fine)
		var = t_fine - 76800.0
		
		return 0 if var.zero?
		
		var = (adc_h - (calib[:h][3] * 64.0 + calib[:h][4] / 16384.0 * var)) * 
			(calib[:h][1] / 65536.0 * (1.0 + calib[:h][5] / 67108864.0 * var * 
			(1.0 + calib[:h][2] / 67108864.0 * var)))
		var = var * (1.0 - calib[:h][0] * var / 524288.0)
		
		if var > 100.0
			var = 100.0
		elsif var < 0.0
			var = 0.0
		end
		
		var
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

if __FILE__ == $0
  bme = BME280.new

  pp bme.update
end
