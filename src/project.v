/*
 * Copyright (c) 2024 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`define default_netname none

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

	wire reset = !rst_n;

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
	anemonesynth_top #(.IO_BITS(IO_BITS)) synth(
		.clk(clk), .reset(!rst_n),
		.tx_pins(tx_pins), .rx_pins(rx_pins)
	);

	wire [RAM_PINS-1:0] data_pins;
	wire [RAM_PINS-1:0] addr_pins;

	wire [11:0] rgb_out;
	wire hsync, vsync;
	PPU #(.RAM_PINS(RAM_PINS)) ppu(
		.clk(clk), .reset(reset),
		.addr_pins(addr_pins), .data_pins(data_pins),
		//.pixel_out(pixel_out),
		.rgb_out(rgb_out),
		//.active(active),
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
	assign uio_out0[7:6] = '0;

	assign data_pins = ui_in_reg[3:0];
	assign rx_pins  = uio_in_reg[7:6];

	assign uio_out0[3:0] = addr_pins;
	assign uio_out0[5:4] = tx_pins;
endmodule
