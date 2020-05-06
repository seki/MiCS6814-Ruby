
class CCS811
	CCS811_ADDRESS  =  0x5B

	CCS811_STATUS = 0x00
	CCS811_MEAS_MODE = 0x01
	CCS811_ALG_RESULT_DATA = 0x02
	CCS811_RAW_DATA = 0x03
	CCS811_ENV_DATA = 0x05
	CCS811_NTC = 0x06
	CCS811_THRESHOLDS = 0x10
	CCS811_BASELINE = 0x11
	CCS811_HW_ID = 0x20
	CCS811_HW_VERSION = 0x21
	CCS811_FW_BOOT_VERSION = 0x23
	CCS811_FW_APP_VERSION = 0x24
	CCS811_ERROR_ID = 0xE0
	CCS811_SW_RESET = 0xFF

	CCS811_BOOTLOADER_APP_ERASE = 0xF1
	CCS811_BOOTLOADER_APP_DATA = 0xF2
	CCS811_BOOTLOADER_APP_VERIFY = 0xF3
	CCS811_BOOTLOADER_APP_START = 0xF4

	CCS811_DRIVE_MODE_IDLE = 0x00
	CCS811_DRIVE_MODE_1SEC = 0x01
	CCS811_DRIVE_MODE_10SEC = 0x02
	CCS811_DRIVE_MODE_60SEC = 0x03
	CCS811_DRIVE_MODE_250MS = 0x04
	
	CCS811_HW_ID_CODE = 0x81
	CCS811_REF_RESISTOR	= 100000

	class StatusBits
		def initialize(data)
			@data = data
		end
		def error?; @data[0] == 1; end
		def data_ready?; @data[3] == 1; end
		def app_valid?; @data[4] == 1; end
		def fw_mode?; @data[7] == 1; end
	end

	def initialize(app_start,
		             mode=CCS811_DRIVE_MODE_1SEC,
								 addr=CCS811_ADDRESS)
		@addr = addr
		@drive_mode = mode
		@int_thresh = 0
		@int_datrdy = 0
    @i2c = MinI2C.new
		@tvoc = 0
		@eco2 = 0

		dev_id = @i2c.i2cget(@addr, CCS811_HW_ID, 1).unpack("C").first
		unless dev_id == CCS811_HW_ID_CODE
			raise "incorrect device id"
		end

		# @i2c.i2cset(@addr, CCS811_SW_RESET, 0x11, 0xE5, 0x72, 0x8A)

		if app_start
			p :app_start
			@i2c.i2cset(@addr, CCS811_BOOTLOADER_APP_START)
			sleep(0.1)
		end

		read_status
		raise "error" if @status.error?
		raise "not fw_mode" unless @status.fw_mode?

		cur = @i2c.i2cget(@addr, CCS811_MEAS_MODE, 1).unpack("C")[0]
		pp cur
		sleep(0.1)

		if cur != mode << 4
			@i2c.i2cset(@addr, CCS811_MEAS_MODE, mode << 4)
		end
		# disable_interrupt
		# set_drive_mode(mode)
  end
	attr_reader :i2c
	
	def set_drive_mode(mode)
		@drive_mode = mode
		write_meas_mode
	end

	def disable_interrupt
		enable_interrupt(false)
	end

	def enable_interrupt(enable=true)
		@int_datardy = enable ? 1 : 0
		write_meas_mode
	end

	def available?
		read_status
		@status.data_ready?
	end

	def read_data
		return nil unless available?
		buf = @i2c.i2cget(@addr, CCS811_ALG_RESULT_DATA, 8)
		@eco2, @tvoc, s, e = buf.unpack("nnCC")
		{ :eCO2 => [@eco2, @eco2 & 0x7fff], :TVOC => [@tvoc, @tvoc & 0x7fff], :status => [s, e]}
		# return ???
	end

	def set_environmental_data(humidity, temperature)
		raise "invalid temperature" if temperature < -25
		raise "invalid temperature" if temperature > 50
		raise "invalid humidity" if humidity < 0
		raise "invalid humidity" if humidity > 100

		rh = (humidity * 512).to_i
		temp = ((temperature + 25) * 512).to_i
		buf = [rh, temp].pack("nn").unpack("C*")
		@i2c.i2cset(@addr, CCS811_ENV_DATA, *buf)
	end

	def read_status
		it = @i2c.i2cget(@addr, CCS811_STATUS, 1).unpack("C")[0]
		@status = StatusBits.new(it)
	end

	def write_meas_mode
		v = @int_thresh << 2 | @int_datardy << 3 | @drive_mode << 4
		@i2c.i2cset(@addr, CCS811_MEAS_MODE, v)
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
			sleep(0.5)
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
			sleep(0.5)
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
	require_relative "./bme280"

	n = 0
	bme = BME280.new
	ccs = CCS811.new(ARGV.shift || nil)
	while true
		n += 1
		sleep 5
		if n >= 10
			v = bme.update
			pp v
			begin
				ccs.set_environmental_data(v[:h], v[:t]) 
			rescue
				p $!
			end
		end
		begin
			pp [ccs.read_data, Time.now]
		rescue
			p $!
		end
		n = n % 10
	end
end
