/*
 * Copyright (c) 2024 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`define default_netname none

`include "synth_common.vh"
`include "ppu_common.vh"

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
	reg [3:0] cfg;
	always @(posedge clk) begin
		reset <= !rst_n;
		// Sample cfg as long as we're in reset
		if (!rst_n) cfg <= ui_in[3:0]; // same as data_pins
	end

	wire rx_source_ui54 = cfg[0];
	wire drive_uio_76   = cfg[0];

	reg vblank_pending;
	wire vblank_ack;
	wire vblank_en = ppu_ctrl[`PPU_CTRL_BIT_SEND_EVENTS];
	always @(posedge clk) begin
		if (reset) begin
			vblank_pending <= 0;
		end else begin
			vblank_pending <= vblank_en && ((vblank_pending && !vblank_ack) || (new_frame && !reset_ppu));
		end
	end

	// Register all inputs and outputs, at least for now
	reg [7:0] ui_in_reg, uio_in_reg, uo_out_reg, uio_out_reg;
	reg [1:0] rx_in_reg;
	wire [7:0] uo_out0, uio_out0;
	always @(posedge clk) begin
		ui_in_reg   <= ui_in;
		uio_in_reg  <= uio_in;
		rx_in_reg   <= rx_source_ui54 ? ui_in[5:4] : uio_in[7:6];
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
		.ppu_ctrl(ppu_ctrl), .ext_tx_request(vblank_pending), .ext_tx_ack(vblank_ack)
	);

	// Disable data sync bypass; it seems to bring setup time margin down to almost zero
	wire sync_data = 1'b1; // ppu_ctrl[`PPU_CTRL_BIT_SYNC_DATA];
	wire dither_out = ppu_ctrl[`PPU_CTRL_BIT_DITHER];
	wire rgb332_out = ppu_ctrl[`PPU_CTRL_BIT_RGB332_OUT];

	wire reset_ppu = reset || !ppu_ctrl[`PPU_CTRL_BIT_RST_N];

	wire [RAM_PINS-1:0] data_pins;
	wire [RAM_PINS-1:0] addr_pins;
	wire [RAM_PINS-1:0] addr_pins_out = reset_ppu ? data_pins : addr_pins; // Loopback data_pins -> addr_pins when the PPU is in reset

	wire [11:0] rgb_out;
	wire [5:0] rgb_dithered_out;
	wire hsync, vsync, active, new_frame;
	wire [1:0] serial_counter;
	PPU #(.RAM_PINS(RAM_PINS), .VPARAMS1(`VPARAMS_64_TEST)) ppu(
		.clk(clk), .reset(reset_ppu),
		.addr_pins(addr_pins), .data_pins(data_pins),
		//.pixel_out(pixel_out),
		.rgb_out(rgb_out), .rgb_dithered_out(rgb_dithered_out),
		.active(active), .new_frame(new_frame),
		.hsync(hsync), .vsync(vsync),
		.serial_counter(serial_counter)
	);

	assign uo_out0 = {
		hsync,
		dither_out ? rgb_dithered_out[0] : rgb_out[0+2], // B0 / B2
		dither_out ? rgb_dithered_out[2] : rgb_out[4+2], // G0 / G2
		dither_out ? rgb_dithered_out[4] : rgb_out[8+2], // R0 / R2
		vsync,
		dither_out ? rgb_dithered_out[1] : rgb_out[0+3], // B1 / B3
		dither_out ? rgb_dithered_out[3] : rgb_out[4+3], // G1 / G3
		dither_out ? rgb_dithered_out[5] : rgb_out[8+3]  // R1 / R3
	};

	//assign uio_oe = 8'b00111111;
	assign uio_oe[5:0] = '1;
	assign uio_oe[7:6] = drive_uio_76 ? 2'b11 : 2'b00;

	assign data_pins = sync_data ? ui_in_reg[3:0] : ui_in[3:0];
	//assign rx_pins  = uio_in_reg[7:6];
	assign rx_pins   = rx_in_reg;

	assign uio_out0[3:0] = addr_pins_out;
	assign uio_out0[5:4] = tx_pins;
	// Active signal is used in GL test even though drive_uio_76 is low
	assign uio_out0[6] = rgb332_out ? (rgb_out[4+1] && drive_uio_76) : active;
	// Pixel clock, rises in the middle of stable uo_out;
	assign uio_out0[7] = (rgb332_out ? rgb_out[8+1] : serial_counter[0]) && drive_uio_76;
endmodule
