# SPDX-FileCopyrightText: © 2024 Toivo Henningsson <toivo.h.h@gmail.com>
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from context_keeper import ContextKeeper

@cocotb.test()
async def test_voices(dut):
	dut._log.info("start")
	clock = Clock(dut.clk, 2, units="us")
	cocotb.start_soon(clock.start())

	preserved = True
	try:
		synth = dut.dut.synth
	except AttributeError:
		preserved = False

	if preserved:
		voice = synth.voice
		ctrl = synth.controller

		OCT_BITS = int(voice.OCT_BITS.value)
		PHASE_BITS = int(voice.PHASE_BITS.value)
		SUBSAMP_BITS = int(voice.SUBSAMP_BITS.value)
		SUPERSAMP_BITS = int(voice.SUPERSAMP_BITS.value)
		SAMP_BITS = SUPERSAMP_BITS + SUBSAMP_BITS
		ACC_BITS = int(voice.ACC_BITS.value)
		MOD_MANTISSA_BITS = int(voice.MOD_MANTISSA_BITS.value)
		SVF_STATE_BITS = int(voice.SVF_STATE_BITS.value)
		PARAM_BIT_LFSR = int(voice.PARAM_BIT_LFSR.value)
		PARAM_BIT_WF0 = int(voice.PARAM_BIT_WF0.value)
		PARAM_BIT_PHASECOMB = int(voice.PARAM_BIT_PHASECOMB.value)
		PARAM_BIT_WFSIGNVOL = int(voice.PARAM_BIT_WFSIGNVOL.value)
		WF_PARAM_BITS = int(voice.WF_PARAM_BITS.value)

		STATE_WORDS = int(voice.STATE_WORDS.value)
		WORD_SIZE = int(voice.WORD_SIZE.value)
		STATE_BITS = int(voice.STATE_BITS.value)
		NUM_VOICES = 1 << int(ctrl.LOG2_NUM_VOICES.value)
		NUM_SAMPLES_PER_VOICE = 1 << int(ctrl.LOG2_NUM_SAMPLES_PER_VOICE.value)
		NUM_SWITCHES_PER_SAMPLE = NUM_VOICES // NUM_SAMPLES_PER_VOICE

		all_wf_mask = 1 + (1 << WF_PARAM_BITS)
		phasecomb_default = (1 << WF_PARAM_BITS) << PARAM_BIT_PHASECOMB
		on_default = (7 << PARAM_BIT_WFSIGNVOL) << (2*WF_PARAM_BITS)

		assert int(voice.USED_STATE_BITS.value) <= int(voice.STATE_BITS.value)

		acc_sign_bit = 1 << (ACC_BITS - 1)
		wave_h = 1 << (PHASE_BITS - 1)
		wave_mask = (1 << PHASE_BITS) - 1
		y_h = 1 << (SVF_STATE_BITS - 1)
		y_mask = (1 << SVF_STATE_BITS) - 1

		assert WORD_SIZE == 16
		assert NUM_VOICES == 4
	else:
		WORD_SIZE = 16
		NUM_VOICES = 4

		with open("test-setup-data.txt", "r") as file:
			STATE_WORDS = int(file.readline())
			state0 = int(file.readline())
			state1 = int(file.readline())

	out_h = 1 << (WORD_SIZE - 1)
	out_mask = (1 << WORD_SIZE) - 1

	# reset
	dut._log.info("reset")
	dut.rst_n.value = 0
	dut.ui_in.value = 0
	dut.uio_in.value = 0
	await ClockCycles(dut.clk, 10)

	dut.rst_n.value = 1

	if preserved:
		voice.d_y.value = 0
		voice.d_v.value = 0
		voice.d_running_counter.value = 0
		voice.d_mods[0].value = 1 << (MOD_MANTISSA_BITS - 2)
		voice.d_mods[1].value = 1 << (MOD_MANTISSA_BITS - 2)
		voice.d_mods[2].value = 0 # 1 << (MOD_MANTISSA_BITS - 2)
		voice.d_fir_offset_lsbs.value = 0 # 1
		voice.d_phase[0].value = 1 << (PHASE_BITS - 3)
		voice.d_phase[1].value = 0
		voice.d_delayed_p.value = 0
		voice.d_delayed_s.value = 0
		voice.d_float_period[0].value = 0
		voice.d_float_period[1].value = 0
		voice.d_params.value = 2*all_wf_mask << PARAM_BIT_WF0
	await ClockCycles(dut.clk, 1)
	if preserved:
		state1 = int(voice.ostate.value)

		voice.d_mods[0].value = 2 << MOD_MANTISSA_BITS
		voice.d_mods[1].value = 3 << MOD_MANTISSA_BITS
		voice.d_mods[2].value = 4 << MOD_MANTISSA_BITS
		voice.d_fir_offset_lsbs.value = 0
		voice.d_phase[0].value = 0 # 8
		voice.d_phase[1].value = 0
		voice.d_delayed_p.value = 0
		voice.d_delayed_s.value = 0
		voice.d_float_period[0].value = 0 # 1 << PHASE_BITS
		#voice.d_float_period[1].value = (2**OCT_BITS-1) << PHASE_BITS # turn off sub-oscillator
		voice.d_float_period[1].value = 4 << PHASE_BITS
		voice.d_params.value = on_default + phasecomb_default
	await ClockCycles(dut.clk, 1)
	if preserved:
		state0 = int(voice.ostate.value)

		with open("test-setup-data.txt", "w") as file:
			file.write(str(STATE_WORDS) + "\n")
			file.write(str(state0) + "\n")
			file.write(str(state1) + "\n")

	mem = [0xffff for i in range(32)]
	for j in range(4):
		for i in range(2,):
			ii = (i + j) % 3
			index = ii+2 + j*8
			mem[index] = (1 << 14)+ (i << 10) + (j << 4) # sweep, sign, float_period
	for j in range(2):
		index = j + j*8
		mem[index] = (1 << 14)+ (j << 10) # sweep, sign

	keeper = ContextKeeper(mem)

	# Form the switched-out states
	for i in range(0, 4):
		state = ((i + 1)&3)*state1 + state0
		for j in range(STATE_WORDS):
			keeper.state[i*STATE_WORDS + j] = state & ((1 << WORD_SIZE) - 1)
			state >>= WORD_SIZE

	dut.rst_n.value = 1

	max_len = 64
	curr_len = 0

	positions = [32*i for i in range(NUM_VOICES)]

	postfix = "" if preserved else "-gl"

	with open("event-data"+postfix+".txt", "w") as file:
		with open("sbio-data.txt", "w" if preserved else "r") as sbio_file:
			#rx = 0
			for i in range(1000*30):
			#for i in range(400):
			#for i in range(900):
				if preserved:
					if int(voice.svf_enable.value)==1 and int(voice.svf_step.value) == 1 and int(voice.wf_index.value) == 0:
						iv = int(ctrl.curr_voice.value)
						y = ((int(voice.y.value) + y_h) & y_mask) - y_h
						fir_offset = int(voice.fir_offset.value)

						p = positions[iv]
						p2 = (p & ~31) | fir_offset
						if p2 < p: p2 += 32
						positions[iv] = p2

						file.write(str(iv) + " ")
						#file.write(str(fir_offset) + " ")
						file.write(str(p2) + " ")
						file.write(str(y) + "\n")

				tx0 = dut.tx_pins.value
				if tx0.is_resolvable:
					tx = tx0.get_value()
					txs = str(tx)
				else:
					tx = 0
					txs = "x"

				rx = keeper.step(tx)
				dut.uio_in.value = rx << 6

				if preserved:
					sbio_file.write(txs + " " + str(rx) + "\n")
				else:
					tx_p, rx_p = sbio_file.readline().split(" ")
					#if tx_p != "x": tx_p = int(tx_p)
					rx_p = int(rx_p)

					#print(i+1)
					assert rx == rx_p  # Failed to reproduce input to DUT?
					assert txs == tx_p # Failed to reproduce output from DUT?

				if keeper.new_out:
					out = ((keeper.out + out_h) & out_mask) - out_h
					keeper.new_out = False

					file.write("4 0 ")
					file.write(str(out) + "\n")

					curr_len += 1
					if curr_len >= max_len: break

				await ClockCycles(dut.clk, 1)


@cocotb.test()
async def test_ppu(dut):
	dut._log.info("start")
	clock = Clock(dut.clk, 2, units="us")
	cocotb.start_soon(clock.start())

	preserved = True
	#preserved = False
	try:
		ram = dut.extram.ram
	except AttributeError:
		preserved = False

	if preserved:
		reg_addr_pal    = 0
		reg_addr_scroll = 16
		reg_addr_cmp_x  = 20
		reg_addr_cmp_y  = 21
		reg_addr_jump1_lsb = 22
		reg_addr_jump2_msb = 23
		reg_addr_sorted_base = 24
		reg_addr_oam_base = 25
		reg_addr_map_base = 26
		reg_addr_tile_base = 27

		reg_addr_gfxmode1 = 28
		reg_addr_gfxmode2 = 29
		reg_addr_gfxmode3 = 30
		reg_addr_display_mask = 31

		copper_addr_bits = 7
		copper_data_bits = 16 - copper_addr_bits
		map_tile_bits = 11

		sorted_base_addr = 0x100
		oam_base_addr = 0x80
		sprite_tile_base_addr = 0x8000
		map_base_addr0 = 0x1000
		map_base_addr1 = 0x2000
		map_tile_base_addr = 0xc000
		copper_base_addr = 0xfffe

		copper_addr_bits = 7
		copper_data_bits = 16 - copper_addr_bits
		map_tile_bits = 11


		#for i in range(65535):
		#	ram[i].value = i

		#gfxmode = [15, 61, 159] # hparams_32_test = [128-1, 127+2, 128-3, 127+32]
		#gfxmode = [15, 48, 159] # hparams_32_test = [128-1, 127+2, 128-16, 127+32]
		gfxmode = [36, 48, 159] # hparams_32_test = [128-4, 127+5, 128-16, 127+32]

		# Copper list
		# -----------
		copper_addr = copper_base_addr

		copper_extra = 64 # Enable fast mode

		for i in range(3):
			data = gfxmode[i]
			ram[copper_addr].value = ((reg_addr_gfxmode1 + i) | copper_extra | (data << copper_addr_bits)) & 0xffff
			copper_addr = (copper_addr + 1) & 0xffff # will wrap after two steps
		for (i, data) in enumerate([sorted_base_addr>>6, oam_base_addr>>7, 0x21<<1, 0xb<<1]):
			ram[copper_addr].value = ((reg_addr_sorted_base + i) | copper_extra | (data << copper_addr_bits)) & 0xffff
			copper_addr += 1
		# TODO: test both even and odd scroll_x for both planes
		for (i, data) in enumerate([0,0,23,26]):
			ram[copper_addr].value = ((reg_addr_scroll + i) | copper_extra | (data << copper_addr_bits)) & 0xffff
			copper_addr += 1

		if False:
			data = 63 - 4 # Don't display sprites for now
			ram[copper_addr].value = ((reg_addr_display_mask) | copper_extra | (data << copper_addr_bits)) & 0xffff
			copper_addr += 1

		table = [0,3,5,7]
		for i in range(16):
			#data = (i | (i << 4)) << 1
			#s, r, g, b = (i >> 3)&1, (i >> 2)&1, (i >> 1)&1, (i >> 0)&1
			#data = (((r << 7) | (g << 4) | (b << 1)) | (0x6d*s)) << 1
			#data = (table[2*r+s] << 6) | (table[2*g+s] << 3) | table[2*b+s]
			i1, i2 = i&3, i>>2
			data = (table[i2] << 6) | (table[max(0, i1-1)] << 3) | table[i1]
			#print(data)

			# Turn off fast mode for the last writes before cmp
			if i >= 16-3: copper_extra = 0

			ram[copper_addr].value = ((reg_addr_pal + i) | copper_extra | (data << copper_addr_bits)) & 0xffff
			copper_addr += 1

		for (i, scroll_x) in enumerate([20,3]):
			data = 512-2*32 + 2*(8 + i*16)
			ram[copper_addr].value = (reg_addr_cmp_y | (data << copper_addr_bits)) & 0xffff
			copper_addr += 1
			data = scroll_x
			ram[copper_addr].value = ((reg_addr_scroll + 2*(1-i)) | (data << copper_addr_bits)) & 0xffff
			copper_addr += 1


		# stop code
		ram[copper_addr].value = 0xffff


		# Pixel data
		# ----------
		# Tile map
		for k in range(16):
			for y in range(8):
				line = 0
				for x in range(8):
					d = abs(x-3) + abs(y-3)
					color = 3 - min(3, abs(k - 3 - d))
					line |= (color & 3) << 2*x
				ram[map_tile_base_addr + y + 8*k].value = line

		# Sprites
		for k in range(16):
			for j in range(2):
				#if k==5: print("k = ", k, "j = ", j)
				for y in range(8):
					line = 0
					for xt in range(8):
						x = j*8 + xt
						d = (abs(x-7)>>1) + abs(y-3)
						#d = abs(y-3)
						#d = (abs(x-7)>>1)
						#d = (abs(xt-3)>>1) + abs(y-3)
						color = 3 - min(3, abs(k - 3 - d))
						line |= (color & 3) << (2*xt)
					ram[sprite_tile_base_addr + y + 8*(j + 2*k)].value = line

					#if k==5: print("line = ", hex(line))

		# Tile map data
		# -------------
		use_2bpp = 1
		for m in range(2):
			map_base_addr = map_base_addr0 if m == 0 else map_base_addr1
			#pal = 1-m
			dd = 7 - m
			for y in range(64):
				for x in range(64):
					p = x if m == 0 else y
					p = p&7
					if p >= 4: p = 7-p
					pal = p
					d = abs(y % (2*dd) - dd) + abs(x % (2*dd) - dd)
					index = d
					always_opaque = (x&1) & (y&1)
					#ram[map_base_addr + x + 64*y].value = index | ((((pal&3) << 1) | use_2bpp) << map_tile_bits)
					ram[map_base_addr + x + 64*y].value = index | (always_opaque << 11) | ((pal&3) << (map_tile_bits + 3))

		# Sprite data
		# -----------
		for i in range(64):
			#xs = 128 - 2 + i*4
			xs = 128+24 - i*5
			ys = 256 - 32 + i*5
			tile = (i&1) + 4
			pal = i&3
			depth = 0

			ram[sorted_base_addr + i].value = (ys&255) | (i << 8) # {id, y}

			ram[oam_base_addr + 2*i].value     = (ys&7) | (tile << 4)
			# {sprite_depth, sprite_pal, sprite_2bpp, sprite_wide, sprite_x} = sprite_attr_x;
			# ram[oam_base_addr + 2*i + 1].value = (xs&511) | 512 | 1024 | ((pal&3)<<11) | ((depth&3)<<13)
			# {sprite_pal, sprite_always_opaque, sprite_depth, sprite_x} = sprite_attr_x;

			pal = pal << 2
			always_opaque = i in (2, 5)
			if i in (1, 5): pal = 15
			if i == 4: pal = 5

			ram[oam_base_addr + 2*i + 1].value = (xs&511) | ((depth&3)<<9) | (always_opaque << 11) | ((pal&15)<<12)

	dut.uio_in.value = 0
	dut.ui_in.value = 0
#	if preserved:
#		dut.ui_in_74.value = 0
#	else:
#		dut.ui_in.value = 0

	# reset
	dut._log.info("reset")
	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	postfix = "" if preserved else "-gl"

	#await ClockCycles(dut.clk, 300 + (32+25)*(64+6)*4)
	#preserved = False

	with open("roio-data.txt", "w" if preserved else "r") as roio_file:
		with open("vga-data"+postfix+".txt", "w") as vga_file:

			for i in range(150 + (32+25)*(64+6)*2):

				for j in range(2):

					addr = dut.addr_pins_out.value
					vga = dut.uo_out.value
					if vga.is_resolvable: vga = str(vga)
					else: vga = "x"

					if preserved:
						data = dut.data_pins.value

						dut.addr_pins.value = addr
						if data.is_resolvable: dut.ui_in.value = int(data)

						# Save addr, data, vga for use in GL test
						if addr.is_resolvable: addr = str(int(addr))
						else: addr = "x"
						if data.is_resolvable: data = str(int(data))
						else: data = "x"

						roio_file.write(addr + " " + data + " " + vga + " \n")

					else:
						addr_p, data_p, vga_p, _ = roio_file.readline().split(" ")
						if data_p != "x": dut.ui_in.value = int(data_p)

						assert addr_p == "x" or str(int(addr)) == addr_p
						assert vga_p == "x" or vga  == vga_p


					await ClockCycles(dut.clk, 1)

				avhsync = dut.avhsync.value
				if avhsync.is_resolvable: avhsync = int(avhsync)
				else: avhsync = -1
				if i == 0: rgb = 0
				else: rgb = int(dut.rgb.value)

				vga_file.write(str(avhsync) + " " + str(rgb) + "\n")


				if False:
					for j in range(2):
						addr = dut.my_addr_pins.value
						if addr.is_resolvable: addr = str(int(addr))
						else: addr = "x"
						vga = dut.uo_out.value
						if vga.is_resolvable: vga = str(vga)
						else: vga = "x"

						if not preserved:
							addr_p, data_p, vga_p, _ = roio_file.readline().split(" ")
							if data_p != "x": dut.ui_in.value = int(data_p)

							assert addr_p == "x" or addr == addr_p
							#assert vga_p == "x" or vga  == vga_p

						await ClockCycles(dut.clk, 1)

						if (preserved):
							data = dut.data_pins.value
							if data.is_resolvable: data = int(data)
							else: data = "x"

							roio_file.write(str(addr) + " " + str(data) + " " + vga + " \n")

					avhsync = dut.avhsync.value
					if avhsync.is_resolvable: avhsync = int(avhsync)
					else: avhsync = -1
					if i == 0: rgb = 0
					else: rgb = int(dut.rgb.value)

					vga_file.write(str(avhsync) + " " + str(rgb) + "\n")

#@cocotb.test()
async def test_simple(dut):
	dut._log.info("start")
	clock = Clock(dut.clk, 2, units="us")
	cocotb.start_soon(clock.start())

	# reset
	dut._log.info("reset")
	dut.rst_n.value = 0
	#dut.ui_in.value = 0
	#dut.ui_in_74.value = 0
	#dut.uio_in.value = 0
	await ClockCycles(dut.clk, 10)

	dut.rst_n.value = 1

	await ClockCycles(dut.clk, 10)
