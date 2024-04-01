# SPDX-FileCopyrightText: © 2024 Toivo Henningsson <toivo.h.h@gmail.com>
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

@cocotb.test()
async def test_adder(dut):
	dut._log.info("Start")

	dut._log.info("start")
	clock = Clock(dut.clk, 2, units="us")
	cocotb.start_soon(clock.start())

	preserved = True
	try:
		data = dut.tx_pins.value
	except AttributeError:
		preserved = False

	# reset
	dut._log.info("reset")
	dut.rst_n.value = 0
	#dut.ui_in.value = 0
	#dut.uio_in.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	dut._log.info("test")
	await ClockCycles(dut.clk, 1)
