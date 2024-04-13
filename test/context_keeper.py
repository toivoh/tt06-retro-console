
class ContextKeeper:
	def __init__(self, mem, IO_BITS=2, PAYLOAD_CYCLES=8, STATE_WORDS=3*12, FULL_STATE_WORDS=4*12):
		# Duplicated from synth_common.vh
		self.TX_SOURCE_SCAN = 0
		self.TX_SOURCE_OUT  = 1
		self.TX_SOURCE_READ = 2

		self.RX_SB_SCAN = 1
		self.RX_SB_READ = 2
		self.RX_SB_WRITE = 3

		self.REG_ADDR_SAMPLE_CREDITS = 0


		self.IO_BITS = IO_BITS
		self.PAYLOAD_CYCLES = PAYLOAD_CYCLES
		self.STATE_WORDS = STATE_WORDS
		self.FULL_STATE_WORDS = FULL_STATE_WORDS
		self.mem = mem

		self.WORD_SIZE = self.PAYLOAD_CYCLES * self.IO_BITS
		self.tx_mask = (1 << self.IO_BITS) - 1

		self.state_index = STATE_WORDS
		self.state = [0 for i in range(FULL_STATE_WORDS)]

		self.rx_counter = 0
		self.rx_header = 0
		self.rx_buffer = 0

		self.tx_buffer = 0

		self.out = 0
		self.new_out = False

	def step(self, rx):
		"""Takes rx, returns tx"""

		if self.rx_counter == 0:
			if (rx&1) != 0:
				self.rx_counter = 1
		elif self.rx_counter == 1:
			self.rx_header = rx
			self.rx_counter += 1
			#print("rx_header = ", self.rx_header)
		else:
			self.rx_buffer = (self.rx_buffer | (rx << self.WORD_SIZE))>> self.IO_BITS
			self.rx_counter += 1

			if self.rx_counter == self.PAYLOAD_CYCLES + 2:
				# Whole payload received
				self.rx_counter = 0

				if self.rx_header == self.TX_SOURCE_SCAN:
					self.tx_buffer = (self.state[self.state_index] << self.IO_BITS) | self.RX_SB_SCAN # including start bits
					self.state[self.state_index] = self.rx_buffer
					self.state_index += 1
					if self.state_index in (self.STATE_WORDS, self.FULL_STATE_WORDS): self.state_index = 0
				elif self.rx_header == self.TX_SOURCE_READ:
					self.tx_buffer = (self.mem[self.rx_buffer] << self.IO_BITS) | self.RX_SB_READ # including start bits
				elif self.rx_header == self.TX_SOURCE_OUT:
					self.out = self.rx_buffer
					self.new_out = True
					# Refill sample credits when receiving a sample
					self.tx_buffer = (((self.REG_ADDR_SAMPLE_CREDITS << 8) | 3) << self.IO_BITS) | self.RX_SB_WRITE # including start bits

		tx = self.tx_buffer & self.tx_mask
		self.tx_buffer >>= self.IO_BITS

		return tx
