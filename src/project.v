/*
 * Copyright (c) 2024 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`define default_netname none

`include "synth_common.vh"

module tt_um_toivoh_retro_console #( parameter RAM_PINS = 4, IO_BITS = 2) (
		input  wire [7:0] ui_in,    // Dedicated inputs
		output wire [7:0] uo_out,   // Dedicated outputs
		input  wire [7:0] uio_in,   // IOs: Input path
		output wire [7:0] uio_out,  // IOs: Output path
		output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
		input  wire       ena,      // will go high when the design is enabled
		input  wire       clk,      // clock
		input  wire       rst_n     // reset_n - low to reset
	);

	//wire reset = !rst_n;
	reg reset;
	always @(posedge clk) reset <= !rst_n;

	// Register all inputs and outputs, at least for now
	reg [7:0] ui_in_reg, uio_in_reg, uo_out_reg, uio_out_reg;
	wire [7:0] uo_out0, uio_out0;
	always @(posedge clk) begin
		ui_in_reg   <= ui_in;
		uio_in_reg  <= uio_in;
		uo_out_reg  <= uo_out0;
		uio_out_reg <= uio_out0;
	end

	assign uo_out  = uo_out_reg;
	assign uio_out = uio_out_reg;

	wire [IO_BITS-1:0] tx_pins, rx_pins;
	wire [7:0] ppu_ctrl;
	anemonesynth_top #(.IO_BITS(IO_BITS)) synth(
		.clk(clk), .reset(reset),
		.tx_pins(tx_pins), .rx_pins(rx_pins),
		.ppu_ctrl(ppu_ctrl)
	);

	wire sync_data = ppu_ctrl[`PPU_CTRL_BIT_SYNC_DATA];

	wire reset_ppu = reset || !ppu_ctrl[`PPU_CTRL_BIT_RST_N];

	wire [RAM_PINS-1:0] data_pins;
	wire [RAM_PINS-1:0] addr_pins;
	wire [RAM_PINS-1:0] addr_pins_out = reset_ppu ? data_pins : addr_pins; // Loopback data_pins -> addr_pins when the PPU is in reset

	wire [11:0] rgb_out;
	wire hsync, vsync, active;
	PPU #(.RAM_PINS(RAM_PINS), .VPARAMS1(`VPARAMS_64_TEST)) ppu(
		.clk(clk), .reset(reset_ppu),
		.addr_pins(addr_pins), .data_pins(data_pins),
		//.pixel_out(pixel_out),
		.rgb_out(rgb_out),
		.active(active),
		.hsync(hsync), .vsync(vsync)
	);

	assign uo_out0 = {
		hsync,
		rgb_out[0+2], // B2
		rgb_out[4+2], // G2
		rgb_out[8+2], // R2
		vsync,
		rgb_out[0+3], // B3
		rgb_out[4+3], // G3
		rgb_out[8+3]  // R3
	};

	assign uio_oe = 8'b00111111;

	assign data_pins = sync_data ? ui_in_reg[3:0] : ui_in[3:0];
	assign rx_pins  = uio_in_reg[7:6];

	assign uio_out0[3:0] = addr_pins_out;
	assign uio_out0[5:4] = tx_pins;
	assign uio_out0[6] = active;
	assign uio_out0[7] = 1'b0;
endmodule
