
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

