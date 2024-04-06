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
