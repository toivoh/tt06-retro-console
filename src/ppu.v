/*
 * Copyright (c) 2024 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "ppu_common.vh"

module axis_scan_x #( parameter BITS=9, COMPARE_COARSE_BITS=2 ) (
		input wire clk,
		input wire reset,
		input wire reset_phase,   // reset value for phase
		input wire [BITS-1:0] reset_counter, // reet value for counter
		input wire enable,

		input wire [2*BITS-1:0] initials, // values to be loaded into counter when phase starts
		input wire [2*BITS-1:0] compares, // compare values to decide when phase ends

		output reg phase,
		output reg [BITS-1:0] counter,
		output wire new_line, // Goes high when a new line will start in the next cycle
		output wire last_hsync,
		output wire last_pixel,
		output wire h_active_end
	);

	// curr_initial uses ~phase compared to curr_compare, since phase will switch right after using curr_initial
	wire [BITS-1:0] curr_initial = phase == 1 ? initials[BITS-1:0] : initials[2*BITS-1:BITS];
	wire [BITS-1:0] curr_compare = phase == 0 ? compares[BITS-1:0] : compares[2*BITS-1:BITS];

	//wire compare_match = (counter == curr_compare);
	wire compare_match_low  = counter[COMPARE_COARSE_BITS-1:0] == curr_compare[COMPARE_COARSE_BITS-1:0];
	wire compare_match_high = counter[BITS-1:COMPARE_COARSE_BITS] == curr_compare[BITS-1:COMPARE_COARSE_BITS];
	wire compare_match = compare_match_low && compare_match_high;
	wire switch_phase = enable && compare_match;

	always @(posedge clk) begin
		if (reset) begin
			phase <= reset_phase;
			counter <= reset_counter;
		end else begin
			if (switch_phase) begin
				counter <= curr_initial;
				phase <= !phase;
			end else begin
				counter <= counter + {{(BITS-1){1'b0}}, enable};
			end
		end
	end

	assign new_line = switch_phase && phase == 1;
	assign last_hsync = switch_phase && phase == 0;
	assign last_pixel = compare_match && phase == 1;
	assign h_active_end = compare_match_high && phase == 1;
endmodule

module axis_scan_y #( parameter BITS=9, NUM_PHASES=4 ) (
		input wire clk,
		input wire reset,
		input wire [PHASE_BITS-1:0] reset_phase,
		input wire enable,

		input wire [BITS*NUM_PHASES-1:0] counts,

		output reg [$clog2(NUM_PHASES)-1:0] phase,
		output reg [BITS-1:0] counter
	);

	localparam PHASE_BITS = $clog2(NUM_PHASES);

	wire [PHASE_BITS-1:0] next_phase = ({1'b0, phase} == NUM_PHASES - 1) ? 0 : phase + 1;
	//reg [PHASE_BITS-1:0] next_phase;

	always @(posedge clk) begin
		if (reset) begin
			phase <= reset_phase;
			//counter <= counts[BITS*reset_phase+BITS-1 -: BITS];
			counter <= 0;
		end else if (enable) begin
			if (counter == 0) begin
				phase <= next_phase;
				counter <= counts[BITS*next_phase+BITS-1 -: BITS];
			end else begin
				counter <= counter - 1;
			end
		end

		// next_phase is only used at the end of a phase, so it's ok to evaulate it with one cycle delay.
		//next_phase <= phase == NUM_PHASES - 1 ? 0 : phase + 1;
	end
endmodule

module raster_scan2 #( parameter X_BITS=9, Y_BITS=8, X_SUBPHASE_BITS=2, Y_SUB_BITS=1 ) (
		input wire clk,
		input wire reset,
		input wire enable,

		input wire [X_BITS-1:0] x0_fp, xe_hsync, x0_bp, xe_active,
		input wire [Y_BITS+Y_SUB_BITS-1:0] y1_active, y1_fp, y1_sync, y1_bp,

		//output reg active, hsync, vsync, active_or_bp,
		//output reg new_line, new_frame, last_pixel,
		//output wire new_line0,

		// If REGISTER_RASTER_SCAN is defined, scan_flags1, x1, y1, and y_lsb1 are one cycle delayed compared to
		// scan_flags0, x0, y0, and y_lsb0; otherwise not

		output wire [`NUM_SCAN_FLAGS-1:0] scan_flags0, scan_flags1,

		output wire [X_BITS-1:0] x1,
		output wire [Y_BITS-1:0] y1,
		output wire y_lsb1,

		output wire [X_BITS-1:0] x_cmp,
		output wire [Y_BITS+Y_SUB_BITS-1:0] y_cmp
	);

	localparam Y_SCAN_BITS = Y_BITS + Y_SUB_BITS;

	localparam NUM_PHASES = 4;
	localparam PHASE_BITS = $clog2(NUM_PHASES);
	localparam PHASE_ACTIVE = 2'd0, PHASE_FP = 2'd1, PHASE_SYNC = 2'd2, PHASE_BP = 2'd3;

	wire [X_BITS-1:0] x0;
	wire [Y_BITS-1:0] y0;
	wire y_lsb0;

`ifdef REGISTER_RASTER_SCAN
	reg [`NUM_SCAN_FLAGS-1:0] scan_flags;
	reg [X_BITS-1:0] x;
	reg [Y_BITS-1:0] y;
	reg y_lsb;

	assign scan_flags1 = scan_flags;
	assign x1 = x;
	assign y1 = y;
	assign y_lsb1 = y_lsb;
`else
	assign scan_flags1 = scan_flags0;
	assign x1 = x0;
	assign y1 = y0;
	assign y_lsb1 = y_lsb0;
`endif

	wire phase_x;
	wire new_line0, last_pixel0, last_pixel_group0;
	wire last_hsync;
	axis_scan_x #(.BITS(X_BITS)) x_scan(
		.clk(clk), .reset(reset),  .enable(enable),
		//.reset_phase(1'b1), .reset_counter(x0_bp),
		.reset_phase(1'b0), .reset_counter(x0_fp),
		.initials({x0_bp, x0_fp}), .compares({xe_active, xe_hsync}),

		.phase(phase_x), .counter(x0),
		.new_line(new_line0), .last_pixel(last_pixel0), .last_hsync(last_hsync),
		.h_active_end(last_pixel_group0)
	);
	//assign new_line0 = enable && phase_x == PHASE_SYNC && x0 == 0;
	assign x_cmp = {x0[X_BITS-1:7], x0[6:5] - 2'd3, x0[4:0]};

	assign scan_flags0[`I_NEW_LINE] = new_line0;
	assign scan_flags0[`I_LAST_PIXEL] = last_pixel0;
	assign scan_flags0[`I_LAST_PIXEL_GROUP] = last_pixel_group0;

	wire [PHASE_BITS-1:0] phase_y;
	wire [Y_SCAN_BITS-1:0] yc0;
	//my_axis_scan #(.BITS(Y_BITS), .NUM_PHASES(NUM_PHASES)) y_scan(
	axis_scan_y #(.BITS(Y_SCAN_BITS), .NUM_PHASES(NUM_PHASES)) y_scan(
		.clk(clk), .reset(reset), .enable(scan_flags0[`I_NEW_LINE]),
		//.reset_phase(PHASE_ACTIVE),
		.reset_phase(PHASE_SYNC),
		.counts({y1_bp, y1_sync, y1_fp, y1_active}),
		.phase(phase_y), .counter(yc0)
	);
	// Invert and remove LSB
	assign y0 = ~yc0[Y_SCAN_BITS-1 -: Y_BITS];
	assign y_lsb0 = ~yc0[0];
	assign y_cmp = (phase_y == PHASE_ACTIVE) ? ~yc0 : 0;

	// If the top X_SUBPHASE_BITS are low, we're in the first subphase.
	wire subphase0 = |x0[X_BITS-1 -: X_SUBPHASE_BITS];


	assign scan_flags0[`I_NEW_FRAME] = new_line0 && phase_y == PHASE_SYNC && yc0 == 0; // TODO: correct?

	wire h_active = (phase_x == 1 && subphase0 == 1);
	wire v_active = (phase_y == PHASE_ACTIVE);
	assign scan_flags0[`I_ACTIVE] = h_active && v_active;
	assign scan_flags0[`I_V_ACTIVE] = v_active;
	assign scan_flags0[`I_HSYNC] = (phase_x == 0 && subphase0 == 1);
	assign scan_flags0[`I_VSYNC] = vsync0;
	assign scan_flags0[`I_ACTIVE_OR_BP] = phase_x;

	reg vsync0;
	always @(posedge clk) begin
`ifdef REGISTER_RASTER_SCAN
		x <= x0;
		y <= y0;
		y_lsb <= y_lsb0;

		scan_flags <= scan_flags0;
`endif

		if (reset) vsync0 <= 0;
		else if (last_hsync) vsync0 <= (phase_y == PHASE_SYNC);
	end
endmodule

module color_index_decoder(
		input wire [3:0] pixel_data,
		input wire pixel_index, // In 2 bpp mode, use the low or high bits of pixel_data?
		input wire [3:0] pal,
		input wire always_opaque,

		output wire [3:0] index,
		output wire _2bpp,
		output wire opaque
	);

	wire [3:0] pal_offset = {pal[3:1], 1'b0};
	wire flip = pal[0];
	assign _2bpp = (pal != '1);

	// 2 bpp decoding
	wire [1:0] data_2bpp = pixel_index == 1'b1 ? pixel_data[3:2] : pixel_data[1:0];
	wire opaque_2bpp = always_opaque || (data_2bpp != '0);
	wire [3:0] index_2bpp0 = opaque_2bpp ? (data_2bpp + pal_offset) : '0;
	wire [3:0] index_2bpp = flip ? {index_2bpp0[1:0], index_2bpp0[3:2]} : index_2bpp0;

	assign index  = _2bpp ? index_2bpp  : pixel_data;
	assign opaque = _2bpp ? opaque_2bpp : (always_opaque || (pixel_data != '0));
endmodule

/*
The sprite_unit module
- Reads sprite data from RAM
- Buffers it
- Delivers it for the current pixel as the raster sweep progresses

The process of reading sprites is done in several steps:
- A list of 64 words (id, y) (idy) sorted by x position
	- Read in order, filter on y hit, store in 4-entry id buffer
- 64 oam entries of 2 words each (attr_x, attr_y)
	- Read into one of 4 sprite buffers
	- attr_y contains tile id and lsbs of y, needed to look up sprite pixels
- Pixel data
	- Read into 32 bit sprite_pixels shift register for sprite buffer
	- Shifted to extract the pixels as well

There are 4 sprite buffers, each can hold data for a sprite while it is being loaded and until it has expired in x.

RAM reading is done using independent agents for the different steps:
- Read address for the sorted buffer, increments when sending an idy read
- Write and read addresses for id buffer, increment when y matching id arrives and when id has been used to read oam respectively
- Write and read addresses for oam, increment when oam data arrives and when it has been used to read pixels respectively
- Write address for pixels, increments to next sprite buffer when pixels have been filled

The write and read addresses for the same buffer are used as head and tail pointers, to check if there is more data
that has been written but not yet read. They are also used in some places to check if there is space for new data without
filling the buffer/making it look empty.
-- Should this be tested in more places? Is there a risk that a buffer can overfill/look empty?

All buffers are reused in a circular fashion. This works since all sprites are expected to be sorted in x order,
but is not ideal if mixing sprites of width 8 and 16; a sprite buffer might become free for a width 8 sprite before the previous
width 16 sprite is freed, but the previous sprite buffer needs to reloaded first.

The later steps are prioritized over the earlier ones if they have something to do.
There is a delay of 4 serial cycles/pixels (16 cycles) between sending an adress and receiving the data.
The shift register dt_sreg keeps track of the type of request that has been sent (according to priority),
and causes the right recepient to take care of the incoming value.

A sprite becomes valid for display when its last pixel data has been loaded, as marked in valid_sprites.
It stops being valid when it has passed its last x coordinate.


Sprite pixel data for the current pixel is collected by looking at one of the 4 sprite buffers on each the 4 cycles
for a given pixel. Many signals hold values related to the current sprite buffer for that cycle.
Some of these are also used to feed back into the sprite fetch machinery, such as updating valid_sprites and catch up.


Backtracking
------------
When there is no space left in the id buffer, the id buffer scan will set scan_on = 0,
wait for all outstanding idy reads to come in, and decrement the address for each one.
-- This should turn the scan back on if it has been turned off!

This only happens when there is a y match that can't be stored in the id buffer,
so non-matches can be skipped over.

Sprite catch-up
---------------
The sprite_pixels shift register is kept in sync with x coordinate so that the lsbs match the pixel to be displayed.
This is normally done by shifting after each pixel, or every other pixel if the sprite is 2 bpp.
This works fine when there is time to load a sprite completely before it should be displayed.

But when a sprite is loaded that is already matching in x, the sprite pixels need to be fast forwarded to the right scan position.
This is done by calculating the number of outstanding shifts the given sprite buffer will have at the next pixel, in curr_catch_up.
The value is stored into sprite_catch_up_counters[sprite_buffer_index].
As long as sprite_catch_up_counters[sprite_buffer_index] > 0, the sprite pixels are shifted, and if there was no other reason do_scan1
to shift the pixels, the counter is decremented.
The try_catch_up flags keep track of which sprite buffers have not yet caught up; those are not displayed.

Wide sprites and 2 bpp sprites
------------------------------
2 bpp sprites consume only 2 bits per pixel, and should only shift sprite_pixels every other pixel.
The sprite_wide signal is used to make a sprite twice as wide and does most of the work:
- Make x_match window twice as wide
- Shift only when x_diff[0] is set
- Adapt initial value for catch up counter

The sprite_2bpp signal is used to change the color index mapping from curr_sprite_pixels and make it depend on
sprite_pal and x_diff[0].

sprite_wide could be used even without sprite_2bpp to just stretch a sprite horizontally.
sprite_2bpp without sprite_wide does not seem that useful, half of the pixel bits are lost.
*/

module sprite_unit #(
		parameter LOG2_SORTED_SIZE=6,
		ID_BUFFER_SIZE=4, // must be equal to NUM_SBUFS
		ID_BITS=6, ADDR_PINS=4, DATA_PINS=4, X_BITS=9, Y_BITS=8,
		SPRITE_X_BITS=3, // for narrow sprites, wide sprites are twice as wide.
		TILE_Y_BITS=3,
		TILE_BITS=10, // an additional lowest bit is set to zero for the first tile fetched and one for the second
		DATA_DELAY=4, FULL_COLOR_BITS=4, COLOR_BITS=2,
		LOG2_NUM_LEVELS=2, BASE_LEVEL=1 // sprite_unit needs three request levels
	) (
		input wire clk,
		input wire reset,
		input wire restart, // Raise at end of line/start of new for at least 4 cycles to reset and restart scan
		input wire visible, // High when x is valid

		input wire [X_BITS-1:0] x, // Current x position on screen (will be used with some delay)
		input wire [Y_BITS-1:0] y, // Current y position on screen
		input wire y_frac,

		input wire [1:0] serial_counter,

		output wire [ADDR_PINS-1:0] addr_pins,
		input wire [DATA_PINS-1:0] data_pins,

		// read_coordinator interface
		// dt_in:  Data type of the current address being sent.
		// dt_out: Data type of the current data being received.
		output wire [2:0] request, // Must have NUM_STAGES bits
		input wire [LOG2_NUM_LEVELS-1:0] dt_in, dt_out,
		input wire [LOG2_NUM_LEVELS*DATA_DELAY-1:0] dt_sreg,

		output wire [3:0] temp_out,
		output wire [1:0] depth_out,

		input wire [15:0] sorted_base_addr, // Must be aligned to   2^LOG2_SORTED_SIZE
		input wire [15:0] oam_base_addr,    // Must be aligned to 2*2^ID_BITS
		input wire [15:0] tile_base_addr    // Must be aligned to 2*2^(TILE_BITS + TILE_Y_BITS)
	);

	// Common code
	// ===========

	localparam NUM_STAGES = 3;
	localparam IDY_INDEX = 0;
	localparam OAM_INDEX = 1;
	localparam PIX_INDEX = 2;

	localparam DT_BASE = BASE_LEVEL;
	localparam DT_IDY = DT_BASE + IDY_INDEX;
	localparam DT_OAM = DT_BASE + OAM_INDEX;
	localparam DT_PIX = DT_BASE + PIX_INDEX;

	localparam LOG2_NUM_SBUFS = 2;
	localparam STAGE_COUNTER_BITS = LOG2_NUM_SBUFS + 1;
	localparam NUM_SBUFS = 2**LOG2_NUM_SBUFS;


	localparam EXTRA_SORTED_ADDR_BITS = LOG2_SORTED_SIZE - STAGE_COUNTER_BITS;
	localparam LOG2_ID_BUFFER_SIZE = $clog2(ID_BUFFER_SIZE);

	genvar i;

	wire first_serial_cycle = (serial_counter == 0);
	wire last_serial_cycle = (serial_counter == 3);


	// Read arbitration and tracking
	// -----------------------------
	// Bit vectors for each stage: did it request access / was granted access / got data back?
	wire [NUM_STAGES-1:0] grant, got;

	generate
		for (i = 0; i < NUM_STAGES; i++) begin
			assign grant[i] = dt_in == DT_BASE + i;
			assign got[i]   = dt_out == DT_BASE + i;
		end
	endgenerate

	// Address out mux
	// ---------------
	// Muxes addresses from the different stages, and then by serial_counter.
	// CONSIDER: Can some of the muxing be done by shift registers, e g attr_y?
	wire [15:0] request_addr[NUM_STAGES];
	wire [15:0] addr = request_addr[dt_in - DT_BASE]; // CONSIDER: does this create an adder? Should just be mux.
	assign addr_pins = addr[serial_counter*ADDR_PINS + ADDR_PINS-1 -: ADDR_PINS];

	// Stage counters
	// --------------
	// Each stage has an out counter for sending addresses and an in counter for receiving data.
	//
	// Stage counters:
	// * out_counters[IDY_INDEX]: Address in sorted list, suplemented by extra_sorted_addr_bits
	// * in_counters[IDY_INDEX], out_counters[OAM_INDEX]: Index into id_buffer, just 2 bits
	// * in_counters[OAM_INDEX], out_counters[PIX_INDEX]: {Sprite buffer index, 1'b0 = attr_y / 1'b1 = attr_x}
	// * in_counters[PIX_INDEX]: {Sprite buffer index, first / second pixel read}

	wire [NUM_STAGES-1:0] inc_out, inc_in;
	// First out_counter has additional bits in the form of extra_sorted_addr_bits
	reg [STAGE_COUNTER_BITS-1:0] out_counters[NUM_STAGES];
	reg [STAGE_COUNTER_BITS-1:0] in_counters[NUM_STAGES];
	wire [STAGE_COUNTER_BITS+1-1:0] next_out_counters[NUM_STAGES];
	wire [STAGE_COUNTER_BITS+1-1:0] next_in_counters[NUM_STAGES];

	generate
		for (i = 0; i < NUM_STAGES; i++) begin
			// Consider: try muxing the adders

			// Override for idy stage: generalized stepping logic to support wider counter and backtracking
			if (i == IDY_INDEX) assign next_out_counters[i] = next_sorted_addr[STAGE_COUNTER_BITS:0];
			else                assign next_out_counters[i] = out_counters[i] + {{(STAGE_COUNTER_BITS){1'b0}}, (last_serial_cycle & grant[i] & inc_out[i])};

			assign next_in_counters[i]  = in_counters[i]  + {{(STAGE_COUNTER_BITS){1'b0}}, (last_serial_cycle & got[i] & inc_in[i])};

			always @(posedge clk) begin
				if (reset || restart) begin
					out_counters[i] <= 0;
					in_counters[i] <= 0;
				end else begin
					out_counters[i] <= next_out_counters[i][STAGE_COUNTER_BITS-1:0];
					in_counters[i]  <= next_in_counters[i][STAGE_COUNTER_BITS-1:0];
				end
			end
		end
	endgenerate

	// Data in shift register
	// ----------------------
	// Store the previous 4 bits so that we can consider the last 8 bits together
	reg [DATA_PINS-1:0] last_data_pins;
	wire [2*DATA_PINS-1:0] data8 = {data_pins, last_data_pins};

	always @(posedge clk) last_data_pins <= data_pins;

	// Stage specific code
	// ===================

	// Sprite scan request out
	// -----------------------
	reg scan_enabled; // Enabled by restart, disabled when we have scanned through whole sorted list
	reg scan_on; // For pausing the scan for backtracking

	// Extend the IDY counter with extra bits
	reg [EXTRA_SORTED_ADDR_BITS-1:0] extra_sorted_addr_bits;
	wire [LOG2_SORTED_SIZE-1:0] sorted_addr = {extra_sorted_addr_bits, out_counters[IDY_INDEX]};

	// Backtracking: grant[IDY_INDEX] steps forward as usual, but dec_idy_out steps backward
	wire signed [1:0] delta_sorted_addr = last_serial_cycle ? (grant[IDY_INDEX] - dec_idy_out) : 0;
	wire signed [LOG2_SORTED_SIZE+1-1:0] delta_sorted_addr_ext = {{(LOG2_SORTED_SIZE-1){1'b0}}, delta_sorted_addr};
	wire [LOG2_SORTED_SIZE+1-1:0] next_sorted_addr = sorted_addr + delta_sorted_addr_ext;

	wire pause_scan;
	wire resume_scan;

	always @(posedge clk) begin
		if (reset || restart) scan_enabled <= !reset; // Disable at reset, enable at restart
		else if (last_serial_cycle && pause_scan) scan_enabled <= 1; // Restart if backtracking
		else if (scan_on && next_sorted_addr[LOG2_SORTED_SIZE]) scan_enabled <= 0;

		// Turn on scan_on at reset, restart, or resume_scan, otherwise turn off if pause_scan
		scan_on <= (reset || restart) || (last_serial_cycle && resume_scan) || (scan_on && !(last_serial_cycle && pause_scan));

		if (reset || restart) extra_sorted_addr_bits <= 0;
		else extra_sorted_addr_bits <= next_sorted_addr[LOG2_SORTED_SIZE-1:STAGE_COUNTER_BITS];
	end

	assign request[IDY_INDEX] = scan_enabled && scan_on;
	assign request_addr[IDY_INDEX] = {sorted_base_addr[15:LOG2_SORTED_SIZE], sorted_addr};


	// Calculate idy_in_flight: is any IDY data waiting to be received? Then we can't resume scanning yet if we are backtracking.
	wire [DATA_DELAY-1:0] dt_sreg_idy;
	generate
		for (i=0; i < DATA_DELAY; i++) assign dt_sreg_idy[i] = (dt_sreg[LOG2_NUM_LEVELS*(i+1)-1 -:LOG2_NUM_LEVELS] == DT_IDY);
	endgenerate
	wire idy_in_flight = |dt_sreg_idy;

	// Sprite scan in
	// --------------
	reg [ID_BITS-1:0] id_buffer[ID_BUFFER_SIZE]; // Sprite ids found matching but waiting to be loaded into sprite buffers

	wire [Y_BITS-1:0] y_diff = y - data8;
	wire y_match = got[IDY_INDEX] && (y_diff[Y_BITS-1:TILE_Y_BITS] == 0);
	reg y_matched0; // Y match is evaluated at serial_cycle == 1 but needed at serial_cycle == 3; save result here in the meantime

	// These counters actually only 2 bits wide, indexing into id_buffer.
	// Ignore top bits not used to index id_buffer -- become unused.
	wire [LOG2_ID_BUFFER_SIZE-1:0] in_counter_idy  = in_counters[IDY_INDEX][LOG2_ID_BUFFER_SIZE-1:0];
	wire [LOG2_ID_BUFFER_SIZE-1:0] out_counter_oam = out_counters[OAM_INDEX][LOG2_ID_BUFFER_SIZE-1:0];

	// ID buffer is considered full if adding one id would make i look empty.
	// This means that it can never be completely full.
	// Consider: Add a register that can differentiate between completely full and completely empty?
	wire [LOG2_ID_BUFFER_SIZE-1:0] in_counter_idy_plus1 = in_counter_idy + 1;
	wire id_buffer_full = in_counter_idy_plus1 == out_counter_oam;

	// Mask sprite on odd/even lines depending on the top two idy bits
	wire [1:0] y_mask = data8[7:6];
	wire y_matched = y_matched0 && !y_mask[y_frac];

	wire can_store_match = scan_on && !id_buffer_full;
	wire y_matched_store = y_matched && can_store_match;
	// idy_backtrack is true when data comes in that makes us decrement sorted_addr:
	// when backtracking needs to be started, and for every subsequent datum while backtracking.
	wire idy_backtrack = (y_matched && !can_store_match) || (got[IDY_INDEX] && !scan_on);

	assign pause_scan = idy_backtrack;
	// To resume scan, there can be no IDY data in flight, we must be backtracking, and there is no point to resume it
	// unless there is somewhere to store at least one new match.
	assign resume_scan = !(scan_on || id_buffer_full || idy_in_flight);

	always @(posedge clk) begin
		// 8 bits y, then 8 bits id
		if (serial_counter == 1) y_matched0 <= y_match; // Check when data8 contains y
		if (last_serial_cycle && y_matched_store) id_buffer[in_counter_idy] <= data8[ID_BITS-1:0]; // Store when data8 contains id
	end

	// Increment in_counter_idy only if y_matched (increment the others always). Assumes IDY_INDEX = 0.
	//assign inc_in = y_matched_store | (-1 << 1);
	assign inc_in = {2'b11, y_matched_store}; // assumes NUM_STAGES = 3
	wire dec_idy_out = idy_backtrack;

	// OAM request out
	// ---------------
	reg oam_req_step; // For each id in, we produce two oam reads. This keeps track of which step we are on.
	reg oam_load_sprite_valid; // Consider: Do we need a register for this?
	wire [ID_BITS-1:0] oam_id = id_buffer[out_counter_oam]; // Current id to load oam data for

	reg [ID_BITS-1:0] sprite_ids[NUM_SBUFS]; // Sprite id for each sprite buffer entry. Used for depth priority.

	// TODO: Wait if attr_y is not used up
	assign request[OAM_INDEX] = (out_counter_oam != in_counter_idy) && !oam_load_sprite_valid;
	assign request_addr[OAM_INDEX] = {oam_base_addr[15:ID_BITS+1], oam_id, oam_req_step}; // load attr_y first, then attr_x

	//assign inc_out = -1 & ~(1 << OAM_INDEX) | (oam_req_step << OAM_INDEX); // increase out counter if loading attr_x
	assign inc_out = {1'b1, oam_req_step, 1'b1}; // assumes NUM_STAGES = 3, OAM_INDEX = 1

	always @(posedge clk) begin
		if (reset || restart) oam_req_step <= 0;
		else if (grant[OAM_INDEX] && last_serial_cycle) oam_req_step <= ~oam_req_step;

		// Is the sprite that we might want to send out an OAM request for in the next serial cycle already valid?
		// TODO: Is this enough to stop overwriting sprites that have not yet been passed?
		//   Since loading pixels has priority over loading more attributes,
		//   one sprite should become valid before we have time to come around to the same sprite buffer,
		//   if the effects of read delay are not excessive?
		if (last_serial_cycle) oam_load_sprite_valid <= valid_sprites[next_out_counters[OAM_INDEX][LOG2_NUM_SBUFS-1:0]];
	end

	generate
		for (i = 0; i < NUM_SBUFS; i++) begin
			always @(posedge clk) begin
				// If we're using oam_id, store it into the sprite buffer
				if (grant[OAM_INDEX] && i == (out_counter_oam & (NUM_SBUFS-1))) begin
					//sprite_ids[i] <= oam_id;
					sprite_ids[i] <= id_buffer[i]; // Assumes that ID_BUFFER_SIZE == NUM_SBUFS
				end
			end
		end
	endgenerate

	// OAM data in
	// -----------
	reg [15:0] attr_x[NUM_SBUFS]; // x coordinate and other sprite attributes
	// attr_y: tile id, y coordinate, and other attributes.
	// TODO: If some attr_y bits are needed after sending the two pixel buffer reads, they need to be stored elsewhere.
	//reg [15:0] attr_y[NUM_SBUFS];
	reg [15:0] attr_y[2]; // Save space, attr_y just used to calculate pixel address at this point

	wire [LOG2_NUM_SBUFS-1:0] oam_pos; // Sprite buffer index for receiving OAM data
	wire oam_step; // Are we receiving attr_y (0) or attr_x (1)?
	assign {oam_pos, oam_step} = in_counters[OAM_INDEX];

	generate
		for (i = 0; i < NUM_SBUFS; i++) begin
			always @(posedge clk) begin
				if (got[OAM_INDEX] && i == oam_pos) begin
					// Scan in attribute data
					//if (oam_step == 0) attr_y[i] <= {data_pins, attr_y[i][15:DATA_PINS]};
					if (oam_step == 1) attr_x[i] <= {data_pins, attr_x[i][15:DATA_PINS]};
				end
			end
		end
		// Special for attr_y of length 2
		for (i = 0; i < 2; i++) begin
			always @(posedge clk) begin
				if (got[OAM_INDEX] && i == oam_pos[0]) begin // match only on oam_pos[0] since we only have two attr_y
					// Scan in attribute data
					if (oam_step == 0) attr_y[i] <= {data_pins, attr_y[i][15:DATA_PINS]};
				end
			end
		end
	endgenerate

	// Sprite pixel request out
	// ------------------------
	//wire [15:0] curr_attr_y = attr_y[out_counters[PIX_INDEX][LOG2_NUM_SBUFS+1-1 -: LOG2_NUM_SBUFS]];
	wire [15:0] curr_attr_y = attr_y[out_counters[PIX_INDEX][1]]; // Special for attr_y of length 2
	// Extract components of attr_y used for calculating the pixel data address
	wire [TILE_Y_BITS-1:0] tile_y = y[TILE_Y_BITS-1:0] - curr_attr_y[TILE_Y_BITS-1:0];
	wire [TILE_BITS-1:0] tile = curr_attr_y[TILE_BITS+TILE_Y_BITS+1-1 -: TILE_BITS];

	// This form for request[PIX_INDEX] means that we won't fetch the second pixel data until we have received
	// both attr_y and attr_x for the sprite buffer.
	// Should often be the case anyway, and since we set sprite_catch_up_counters based on attr_x
	// when the second sprite pixel data arrives, we should wait like this.
	assign request[PIX_INDEX] = out_counters[PIX_INDEX] != in_counters[OAM_INDEX];
	// out_counters[PIX_INDEX][0] tells whether it's the first or second sprite data, and provides an additional tile id bit.
	assign request_addr[PIX_INDEX] = {tile_base_addr[15:TILE_BITS+1+TILE_Y_BITS], tile, out_counters[PIX_INDEX][0], tile_y};

	// Sprite pixels in
	// ----------------

	// From sprite pixel output
	wire [LOG2_NUM_SBUFS-1:0] curr_sprite_buf = serial_counter;
	wire scan_curr_sprite; // Should the pixel shift register for curr_sprite_buf be shifted?


	reg [31:0] sprite_pixels[NUM_SBUFS];
	reg [NUM_SBUFS-1:0] valid_sprites;

	wire [LOG2_NUM_SBUFS-1:0] pix_pos; // Sprite buffer to receive pixel data for
	wire final_pixels_in; // More conditions are needed to check that the final pixels actually being received
	assign {pix_pos, final_pixels_in} = in_counters[PIX_INDEX];

	/*
	always @(posedge clk) begin
		if (reset || restart) valid_sprites <= 0;
		else begin
			if (last_serial_cycle && got[PIX_INDEX] && final_pixels_in) begin
				valid_sprites <= valid_sprites | (1 << pix_pos);
			end
		end
	end
	*/

	localparam SPRITE_SCAN_BITS = $clog2(32/DATA_PINS);
	reg [SPRITE_SCAN_BITS-1:0] sprite_catch_up_counters[NUM_SBUFS];
	wire [NUM_SBUFS-1:0] try_catch_up;

//	wire [SPRITE_SCAN_BITS-1:0] curr_catch_up = x_match && !(reset || restart) ? x_diff[SPRITE_SCAN_BITS-1:0] : '1;
	// Only every other pixel needs catch up for wide sprites
	wire [SPRITE_SCAN_BITS:0] curr_catch_up0 = (x_diff[SPRITE_SCAN_BITS:0] + 1) >> sprite_wide;
	wire [SPRITE_SCAN_BITS-1:0] curr_catch_up = x_match && !(reset || restart) ? curr_catch_up0[SPRITE_SCAN_BITS-1:0] : '0;

	generate
		for (i = 0; i < NUM_SBUFS; i++) begin
			// ### Logic for sprite pixels for sprite buffer i
			// Pixel data is received for all 4 cycles of a serial cycle.
			// Other updates are done of the cycle when i == curr_sprite_buf, in sync with sprite pixel output.
			// Many signals contain values that apply to the sprite buffer with index curr_sprite_buf.

			wire pix_pos_hit = (got[PIX_INDEX] && i == pix_pos); // Did we receive pixel data for this buffer?
			wire curr_sprite_match = (i == curr_sprite_buf); // Is this buffer being processed by sprite pixel output this cycle?
			wire scan_hit = scan_curr_sprite && curr_sprite_match; // Does sprite pixel output want to shift the pixel data?
			wire do_scan1 = pix_pos_hit || scan_hit; // Does sprite pixel input/output want to shift the pixel data?

			assign try_catch_up[i] = sprite_catch_up_counters[i] != '0;
			wire do_scan = do_scan1 || try_catch_up[i];
			wire catch_up = try_catch_up[i] && !do_scan1; // We can catch up if try_catch_up[i] is the only reason to shift the data

			always @(posedge clk) begin
				if (do_scan) begin
					// Scan in pixel data
					sprite_pixels[i] <= {data_pins, sprite_pixels[i][31:DATA_PINS]};
					//sprite_pixels[i] <= {(scan_hit ? 4'h5 : data_pins), sprite_pixels[i][31:DATA_PINS]}; // shift in constant data if not inputting, for debugging
				end

				//if (reset || restart) valid_sprites[i] <= 0;
				// Don't reset valid_sprites until the last serial cycle, should allow restart to be high for the last visible pixel?
				if (reset || (restart && last_serial_cycle)) valid_sprites[i] <= 0;
				// Sets the valid flag slightly too soon, but it shouldn't be used until the sprite is actually valid?
				else if (pix_pos_hit && final_pixels_in) valid_sprites[i] <= 1;
				else if (curr_sprite_match && x_after) valid_sprites[i] <= 0;

				// Did the final pixels come in for this buffer?
				// curr_sprite_match is need to make curr_catch_up apply to the correct sprite buffer.
				// TODO: The condition seems redundant; pix_pos_hit contains got[PIX_INDEX]
				if ((reset || restart) || (pix_pos_hit && curr_sprite_match && got[PIX_INDEX] && final_pixels_in)) sprite_catch_up_counters[i] <= curr_catch_up;
				// Otherwise, try to catch up. Will not be able to catch up while sprite pixel data is still being shifted in.
				else sprite_catch_up_counters[i] <= sprite_catch_up_counters[i] - {{(SPRITE_SCAN_BITS-1){1'b0}}, catch_up};
			end
		end
	endgenerate


	// Sprite pixel scan
	// =================
	localparam EXTRA_ID_BITS = 1; // Workaround for last sprite disappearing sometimes. CONSIDER: better workaround?

	reg [FULL_COLOR_BITS-1:0] top_color, sprite_out_color;
	reg [ID_BITS+EXTRA_ID_BITS-1:0] top_prio;
	reg [1:0] top_depth, sprite_out_depth;

	wire [2*COLOR_BITS-1:0] curr_sprite_pixels = sprite_pixels[curr_sprite_buf][2*COLOR_BITS-1:0];
	// TODO: share sprite id multiplexer?

	wire sprite_try_catch_up = try_catch_up[curr_sprite_buf];

	// Determine LSB of id buffer index based on out_counter_oam: which sprite ids have recently been loaded?
	//wire [LOG2_ID_BUFFER_SIZE-1:0] diff_sp_index = curr_sprite_buf - out_counter_oam;
	//wire sprite_id_index_msb = !diff_sp_index[LOG2_NUM_SBUFS];
	//wire [ID_BITS-1:0] sprite_id = id_buffer[{sprite_id_index_msb, curr_sprite_buf}];
	wire [ID_BITS-1:0] sprite_id = sprite_ids[curr_sprite_buf];

	wire [15:0] sprite_attr_x = attr_x[curr_sprite_buf];
	wire [X_BITS-1:0] sprite_x;
	wire sprite_wide, sprite_2bpp;
	//wire [1:0] sprite_pal;
	wire [1:0] sprite_depth;
	//assign {sprite_depth, sprite_pal, sprite_2bpp, sprite_wide, sprite_x} = sprite_attr_x[X_BITS+6-1:0];
	wire [3:0] sprite_pal;
	wire sprite_always_opaque;
	assign {sprite_pal, sprite_always_opaque, sprite_depth, sprite_x} = sprite_attr_x;

	wire sprite_valid = valid_sprites[curr_sprite_buf];

	wire [X_BITS+1-1:0] x_diff = x - sprite_x;
	//wire x_match = (x_diff[X_BITS-1:SPRITE_X_BITS] == 0) && visible;
	wire x_match = (x_diff[X_BITS-1:SPRITE_X_BITS+1] == 0) && (sprite_wide || x_diff[SPRITE_X_BITS] == 0) && visible;
	wire x_after = (x_diff[X_BITS] == 0) && !x_match && visible;

/*
	//wire [FULL_COLOR_BITS-1:0] curr_sprite_color = curr_sprite_pixels;
	wire [COLOR_BITS-1:0] curr_sprite_color_2bpp_0 = x_diff[0] ? curr_sprite_pixels[3:2] : curr_sprite_pixels[1:0];
	wire [FULL_COLOR_BITS-1:0] curr_sprite_color_2bpp = {curr_sprite_color_2bpp_0 == 0 ? 2'b0 : sprite_pal, curr_sprite_color_2bpp_0};
	wire [FULL_COLOR_BITS-1:0] curr_sprite_color = sprite_2bpp ? curr_sprite_color_2bpp : curr_sprite_pixels;

	wire opaque = curr_sprite_color != 0; // TODO: base on curr_sprite_color_2bpp_0 if sprite_2bpp?
*/

	wire [3:0] curr_sprite_color;
	wire opaque;
	color_index_decoder index_decoder(
		.pixel_data(curr_sprite_pixels), .pixel_index(x_diff[0]), .pal(sprite_pal), .always_opaque(sprite_always_opaque),
		.index(curr_sprite_color), .opaque(opaque), ._2bpp(sprite_2bpp)
	);
	assign sprite_wide = sprite_2bpp;

	wire sprite_hit = (sprite_valid && x_match) && opaque && !sprite_try_catch_up;
	assign scan_curr_sprite = sprite_valid && x_match && (!sprite_wide || x_diff[0]);

	// The last sprite id will always be behind everything except the background color
	// if curr_prio is used to check if we had a sprite hit
	wire [ID_BITS+EXTRA_ID_BITS-1:0] curr_prio  = sprite_hit ? {1'b0, sprite_id} : '1; // assumes EXTRA_ID_BITS = 1
	wire [1:0] curr_depth                       = sprite_hit ? sprite_depth      : '1;
	wire [FULL_COLOR_BITS-1:0]       curr_color = sprite_hit ? curr_sprite_color : '0; // TODO: other default color?

	wire replace_pixel = (opaque && curr_prio <= top_prio) || first_serial_cycle;

	always @(posedge clk) begin
		if (replace_pixel) begin
			top_color <= curr_color;
			top_prio <= curr_prio;
			top_depth <= curr_depth;
		end
		if (first_serial_cycle) begin
			sprite_out_color <= top_color;
			sprite_out_depth <= top_depth;
		end
	end
	assign temp_out  = sprite_out_color;
	assign depth_out = sprite_out_depth;
endmodule


module priority_encoder8(
		input wire [7:0] active,
		output wire [2:0] level
	);

	genvar i;

	wire [3:0] active1;
	wire level1[4];

	wire [1:0] active2;
	wire [1:0] level2[2];

	generate
		for (i=0; i < 4; i++) begin
			assign active1[i] = active[2*i] | active[2*i+1];
			assign level1[i]  = active[2*i+1];
		end

		for (i=0; i < 2; i++) begin
			assign active2[i]   = active1[2*i] | active1[2*i+1];
			assign level2[i][1] = active1[2*i+1];
			assign level2[i][0] = active1[2*i+1] ? level1[2*i+1] : level1[2*i];
		end
	endgenerate

	assign level[2]   = active2[1];
	assign level[1:0] = active2[1] ? level2[1] : level2[0];

	// For debugging
	wire [3:0] level1_cat = {level1[3], level1[2], level1[1], level1[0]};
	wire [1:0] level2_0 = level2[0];
	wire [1:0] level2_1 = level2[1];
endmodule


module read_coordinator #( parameter NUM_LEVELS=8, DATA_DELAY=4 )
	(
		input wire clk,
		input wire reset, // reset at restart?
		input wire enable,

		input wire [NUM_LEVELS-1:1] request, // The zeroth level is implied
		output wire [$clog2(NUM_LEVELS)-1:0] addr_level, data_level,
		output reg [$clog2(NUM_LEVELS)*DATA_DELAY-1:0] levels_sreg
	);
	localparam LOG2_NUM_LEVELS = $clog2(NUM_LEVELS);

	// Priority encoder
	// ================

	wire [2:0] prio_level;
	priority_encoder8 prio_enc(.active({{(8-NUM_LEVELS){1'b0}}, request, 1'b0}), .level(prio_level));
	assign addr_level = prio_level[LOG2_NUM_LEVELS-1:0];


	// Data type shift register
	// ========================
	// Keeps track of the type of each transaction where the address has been sent but the data not yet received,
	// to know what logic should handle the data when it arrives.
	//reg [LOG2_NUM_LEVELS*DATA_DELAY-1:0] levels_sreg;
	assign data_level = levels_sreg[LOG2_NUM_LEVELS-1:0];

	wire [LOG2_NUM_LEVELS-1:0] addr_level_in = reset ? '0 : addr_level;
	always @(posedge clk) begin
		// During reset, shift in lowest priority level (idle); reset in 4 cycles
		if (reset || enable) levels_sreg <= {addr_level_in, levels_sreg[LOG2_NUM_LEVELS*DATA_DELAY-1:LOG2_NUM_LEVELS]};
	end
endmodule

module copper #(
		parameter ADDR_PINS=4, DATA_PINS=4, ADDR_BITS=16, WADDR_BITS=7, WADDR_BITS_USED=7, WDATA_BITS=9,
		DATA_DELAY=4,
		X_CMP_BITS=9, Y_CMP_BITS=9, REG_ADDR_CMP=0,
		LOG2_NUM_LEVELS=1, BASE_LEVEL=1
	) (
		input wire clk,
		input wire reset,
		input wire restart,

		output wire wen, // apply writes only when serial_counter == 2 or 3 and wen is high
		output wire [WADDR_BITS-1:0] waddr,
		output wire [WDATA_BITS-1:0] wdata,

		input wire [1:0] serial_counter,

		output wire request,
		input wire [LOG2_NUM_LEVELS-1:0] dt_in, dt_out,
		input wire [LOG2_NUM_LEVELS*DATA_DELAY-1:0] dt_sreg,

		output wire [ADDR_PINS-1:0] addr_pins,
		input wire [DATA_PINS-1:0] data_pins,

		input wire [X_CMP_BITS-1:0] x_cmp,
		input wire [Y_CMP_BITS-1:0] y_cmp,

		input wire [15:0] start_addr
	);

	genvar i;

	wire grant = dt_in  == BASE_LEVEL;
	wire got   = dt_out == BASE_LEVEL;

	// Calculate data_in_flight: is any data waiting to be received?
	wire [DATA_DELAY-1:0] dt_sreg_copper_data;
	generate
		for (i=0; i < DATA_DELAY; i++) assign dt_sreg_copper_data[i] = (dt_sreg[LOG2_NUM_LEVELS*(i+1)-1 -:LOG2_NUM_LEVELS] == BASE_LEVEL);
	endgenerate
	//wire data_in_flight = |dt_sreg_copper_data;
	// Ignore later data in flight in fast mode
	wire data_in_flight = dt_sreg_copper_data[DATA_DELAY-1] || (!fast_mode && |dt_sreg_copper_data[DATA_DELAY-2:0]);

	reg on, store_valid; // These registers may only be updated at serial_counter = 3
	reg [15:0] store; // waiting store

	reg cmp_on; // Delay the next write until compare match?
	reg cmp_type; // Compare on x (0) or y (1)?
	reg [WDATA_BITS-1:0] cmp;

	reg fast_mode;

	assign waddr = store[WADDR_BITS-1:0];

	// Probably want a sneak path for wdata to support high throughput
	assign wdata = store[15 -: WDATA_BITS]; // No sneak path yet
	//assign wdata[WDATA_BITS-4-1:0] = store[11 -: WDATA_BITS-4]; // No sneak path yet
	//assign wdata[WDATA_BITS-1 -: 4] = got ? data_pins : store[15:12];
	//assign wdata[WDATA_BITS-1 -: 4] = store[15:12];

	reg [ADDR_BITS-1:0] addr_reg;
	wire [15:0] addr = addr_reg;
	assign addr_pins = addr[serial_counter*ADDR_PINS + ADDR_PINS-1 -: ADDR_PINS];

	// Update store_valid at serial_counter == 3
	assign request = on && !data_in_flight && !store_valid;

	wire delta_addr = grant && (serial_counter == 3);
	always @(posedge clk) begin
		if (reset || restart) begin
			addr_reg <= start_addr[ADDR_BITS-1:0];
			if (serial_counter == 3 || reset) begin // Assumes that restart will be high when serial_counter = 3
				on <= 1; // TODO: Don't turn on at reset
				store_valid <= 0;
			end
			fast_mode <= 0;
		end else begin
			if (serial_counter == 3 && wen && cmp_waddr_match && (waddr[1:0] == 2'b11)) begin
				// Jump, prepare by writing cmp without activating compare
				addr_reg <= {wdata[WDATA_BITS-1 -: 8], cmp[WDATA_BITS-1 -: 8]};
			end else begin
				addr_reg <= addr_reg + {{(ADDR_BITS-1){1'b0}}, delta_addr};
			end

			// Turn off if there is a write to the highest register number
			if (serial_counter == 3 && store_valid && &waddr[WADDR_BITS_USED-1:0]) on <= 0;
			// store_valid stays true as long as wen is false
			if (serial_counter == 3) store_valid <= (on && got) || (store_valid && !wen);
		end

		if (on && got && !store_valid) begin
			if (serial_counter == 0) store[ 3: 0] <= data_pins;
			if (serial_counter == 1) store[ 7: 4] <= data_pins;
			if (serial_counter == 2) store[11: 8] <= data_pins;
			if (serial_counter == 3) store[15:12] <= data_pins;

			if (serial_counter == 3) fast_mode <= store[6]; // update only when serial_counter == 3
		end
	end

	wire [WDATA_BITS-1:0] xy_cmp = cmp_type == 1 ? y_cmp : x_cmp;
	wire cmp_match = (xy_cmp >= cmp);

	assign wen = store_valid && on && (!cmp_on || cmp_match);

	// Internal register writes
	// ------------------------
	// Two register addresses for cmp; cmp_type is set depending on which one is used
	// Two register addresses for jumping
	//
	//     REG_ADDR_CMP:     cmp_x
	//     REG_ADDR_CMP + 1: cmp_y
	//     REG_ADDR_CMP + 2: just write cmp
	// ....REG_ADDR_CMP + 3: jump (don't write cmp)
	wire [31:0] reg_addr_cmp = REG_ADDR_CMP;
	wire cmp_waddr_match = waddr[WADDR_BITS_USED-1:2] == reg_addr_cmp[WADDR_BITS_USED-1:2];
	always @(posedge clk) begin
		if (serial_counter == 3 && wen && cmp_waddr_match && (waddr[1:0] != 2'b11)) begin
			cmp <= wdata;
		end
		if (reset || restart) cmp_on <= 0;
		else if (serial_counter == 3 && wen) begin
			// Turn on if writing cmp for cmp_x or cmp_y, turn off if writing something else
			cmp_on <= cmp_waddr_match && (waddr[1] == 0);
			cmp_type <= waddr[0];
		end
	end
endmodule

/*
The tilemap_unit module
- Handles two tilemap planes
- The planes alternate potential RAM access every other pixel
- Each plane
	- sends a read of the id/attribute data a certain number of pixels in advance
	- bounces the id/attribute data when it arrives to send a read for the pixel data
	- buffers 16 bits of pixel data
	- double buffers the attribute -- current, and most recently read

If there was only one plane, it could send reads an exact number of pixels before they are needed.
Since each plane only gets access every other frame, it needs to be able to delay the output an extra pixel
depending on odd/even x position compared to when the plane has access.
The current attribute can just be updated when the right pixel comes.

The pixel shift register has to be updated when the pixel data arrives. By shifting the first three
and the last nibble independently, pixels can be shifted in early or late.
The last nibble holds the pixel data to be displayed right now.
- For an early update, a bypass path is used to update it as soon as the first nibble comes in
- For a late update, the previous value is held as long as possible

The whole request and update arrangement is a bit of an intricate dance where all the pieces need to fit together
to make the end result work correctly.

The plane that gets updated has new valid pixels and current attribute at most one cycle into the serial cycle/pixel,
the plane that is not updated that pixel has a valid pixel through the whole serial cycle.
If there is a need to access one pixel value each cycle, reorder the planes depending on which one has read priority.

The tilemap_unit assumes that it has the highest RAM priority and will always be granted read access.
No state changes are triggered by being granted a read access though,
- receiving id+attribute data triggers pixel data read (bounce the address) and storing the attribute
- receiving pixel data triggers storing pixel data and updating the current attribute
The load input can be used to block loading of one or both planes.
*/
module tilemap_unit #(
		parameter ADDR_PINS=4, DATA_PINS=4, X_BITS=9, Y_BITS=8, TILE_X_BITS=3, TILE_Y_BITS=3, TILE_BITS=11, MAP_X_BITS=6, MAP_Y_BITS=6,
		ATTR_BITS=5,
		FULL_COLOR_BITS=4, COLOR_BITS=2,
		LOG2_NUM_LEVELS=2, BASE_LEVEL=1 // tilemap_unit needs two request levels: id+attr, pixels
	) (
		input wire clk,
		input wire reset,
		input wire [1:0] load,    // Load data for which planes? Raise 16 pixels before display starts should be enough?
		input wire [1:0] display, // Show pixels for which planes?

		input wire [X_BITS-1:0] x, // Current x position on screen (will be used with some delay)
		input wire [Y_BITS-1:0] y, // Current y position on screen

		input wire [MAP_X_BITS+TILE_X_BITS-1:0] scroll_x0, scroll_x1,
		input wire [MAP_Y_BITS+TILE_Y_BITS-1:0] scroll_y0, scroll_y1,

		input wire [1:0] serial_counter,

		output wire [ADDR_PINS-1:0] addr_pins,
		input wire [DATA_PINS-1:0] data_pins,

		// read_coordinator interface
		// dt_in:  Data type of the current address being sent.
		// dt_out: Data type of the current data being received.
		output wire [1:0] request,
		input wire [LOG2_NUM_LEVELS-1:0] dt_in, dt_out,

		output wire [3:0] pixel_out,
		output wire [1:0] depth_out,

		input wire [15:0] map_base_addr0, map_base_addr1, // Must be aligned to 2^(MAP_X_BITS + MAP_Y_BITS)
		input wire [15:0] tile_base_addr                  // Must be aligned to 2^(TILE_BITS + TILE_Y_BITS)
	);

	// Common code
	// ===========

	// Reading map pixels currently has priority over reading id
	// There should never be a conflict unless scroll_x is changed mid scanline.
	// To switch priority, update DT_MAP, DT_MAP_PIXELS, order in request, address out mux
	localparam DT_MAP        = BASE_LEVEL;
	localparam DT_MAP_PIXELS = BASE_LEVEL + 1;

	localparam PLANE_X_BITS = MAP_X_BITS + TILE_X_BITS;
	localparam PLANE_Y_BITS = MAP_Y_BITS + TILE_Y_BITS;


	genvar i;

	wire first_serial_cycle = (serial_counter == 0);
	wire last_serial_cycle = (serial_counter == 3);

	// Read arbitration and tracking
	// -----------------------------
	wire request_map;
	wire request_map_pixels;
	assign request = {request_map_pixels, request_map};

	// Not used
	//wire granted_map        = request_map && !request_map_pixels;
	//wire granted_map_pixels = request_map_pixels;

	// Address out mux
	// ---------------
	wire [15:0] map_addr;
	wire [ADDR_PINS-1:0] map_addr_bits = map_addr[serial_counter*ADDR_PINS + ADDR_PINS-1 -: ADDR_PINS];
	assign addr_pins = request_map_pixels ? map_pixel_addr_bits : map_addr_bits;

	// Tile planes
	// ===========
	reg [15:0] map_pixels[2];
	reg [ATTR_BITS-1:0] next_attr[2], attr[2];

	wire ram_plane = x[0]; // Which plane has RAM access this serial cycle/pixel

	wire [PLANE_X_BITS-1:0] scroll_x = ram_plane ? scroll_x1 : scroll_x0;
	wire [PLANE_Y_BITS-1:0] scroll_y = ram_plane ? scroll_y1 : scroll_y0;

	wire [PLANE_X_BITS-1:0] xp = x + scroll_x;
	wire [PLANE_Y_BITS-1:0] yp = y + scroll_y;

	// Split plane coordinates into within tile and between tile
	wire [TILE_X_BITS-1:0] tile_xp;
	wire [MAP_X_BITS-1:0] map_xp;
	assign {map_xp, tile_xp} = xp;
	wire [TILE_Y_BITS-1:0] tile_yp;
	wire [MAP_Y_BITS-1:0] map_yp;
	assign {map_yp, tile_yp} = yp;

	wire [15:0] map_base_addr = ram_plane ? map_base_addr1 : map_base_addr0;
	assign map_addr = {map_base_addr[15:MAP_X_BITS+MAP_Y_BITS], map_yp, map_xp};

	// When to trigger a request for new id+attribute data?
	// Will affect the scroll offset
	//wire request_map0 = (tile_xp == 0) || (tile_xp == '1); // Gives problems because map_xp is different in the two cases
	wire request_map0 = (tile_xp == 1) || (tile_xp == 2);
	//wire request_map0 = (tile_xp == 3) || (tile_xp == 4);
	//wire request_map0 = (tile_xp == 5) || (tile_xp == 6);
	//wire request_map0 = tile_xp[TILE_X_BITS-1:1] == 0;

	assign request_map = load[ram_plane] && request_map0;
	assign request_map_pixels = (dt_out == DT_MAP);
	wire store_attr = request_map_pixels;
	wire store_map_pixels = (dt_out == DT_MAP_PIXELS);

	reg [DATA_PINS-1:0] last_data_pins;
	// Delay by 3 bits so that we can insert the 3 lowest bits based on y when forming the pixel adress
	wire [DATA_PINS-1:0] delayed_data_pins = {data_pins[0], last_data_pins[DATA_PINS-1:1]};

	// Form pixel read adress on the fly based on incoming id data
	// {tile_base_addr[15:TILE_BITS+TILE_Y_BITS], tile_index, yp}
	reg [ADDR_PINS-1:0] map_pixel_addr_bits;
	always @(*) begin
		// Assumes TILE_Y_BITS = 3, DATA_PINS = ADDR_PINS = 4
		case (serial_counter)
			0: map_pixel_addr_bits = {delayed_data_pins[3], tile_yp};
			1: map_pixel_addr_bits = delayed_data_pins;
			2: map_pixel_addr_bits = delayed_data_pins;
			3: map_pixel_addr_bits = {tile_base_addr[15:TILE_BITS+TILE_Y_BITS], delayed_data_pins[TILE_BITS-9-1:0]};
		endcase
	end

	always @(posedge clk) begin
		last_data_pins <= data_pins;
	end

	// For each plane, should we advance map_pixels[i] this pixel for display purposes?
	// Also used for other even/odd determination.
	wire [1:0] scan_plane0 = {x[0] ^ scroll_x1[0], x[0] ^ scroll_x0[0]};

	// Attempt to handle scan_plane when updating scroll_x mid scan line -- not working as intended
//	reg [1:0] scroll_x_lsb; // CONSIDER: store alternating values (negate each pixel) to avoid need of xor
//	wire [1:0] scan_plane = {x[0] ^ scroll_x_lsb[1], x[0] ^ scroll_x_lsb[0]};
	wire [1:0] scan_plane = scan_plane0;

	// Update shift registers and attributes per plane
	generate
		for (i=0; i < 2; i++) begin
			wire ram_plane_match = (i == ram_plane);
			wire scan = scan_plane[i] && last_serial_cycle; // shift for display purposes?
			wire store_here = store_map_pixels && (ram_plane == i); // store incoming pixels?
			wire scan_top = store_here || scan; // shift the top three nibbles?
			wire scan_bottom_late = scan_top && last_serial_cycle; // late bottom update is on last serial cycle
			wire scan_bottom_early = store_here && first_serial_cycle && early; // early bottom update is on first serial cycle
			wire scan_bottom = scan_bottom_early || scan_bottom_late; // shift the bottom nibble?

			// Recirculate pixels if not storing new ones, to reduce glitches when changing scroll_x mid scan line
			wire [DATA_PINS-1:0] data_in = store_here ? data_pins : map_pixels[i][DATA_PINS-1:0];

			// Replace the pixel data early if we are going to shift it after the next pixel
			wire early = !scan_plane0[i];

			always @(posedge clk) begin
				if (scan_top)    map_pixels[i][15:DATA_PINS] <= {data_in, map_pixels[i][15:2*DATA_PINS]};
				if (scan_bottom) map_pixels[i][DATA_PINS-1:0] <= scan_bottom_early ? data_pins : map_pixels[i][2*DATA_PINS-1 -: DATA_PINS];

				if (ram_plane_match) begin
					if (store_attr) begin
						// Assumes ATTR_BITS = 5
						if (serial_counter == 2) next_attr[i][ATTR_BITS-DATA_PINS-1 : 0] <= data_pins[3];
						if (serial_counter == 3) next_attr[i][ATTR_BITS-1 -: DATA_PINS] <= data_pins;
					end

					// Update current attribute early or late
					if (store_here && (early || last_serial_cycle)) attr[i] <= next_attr[i];
					//if (store_here && (early || last_serial_cycle)) scroll_x_lsb[i] <= i == 0 ? scroll_x0[0] : scroll_x1[0];
				end
			end
		end
	endgenerate

//	wire [3:0] pixels0 = map_pixels[0][3:0];
//	wire [3:0] pixels1 = map_pixels[1][3:0];

	// TODO: better way to mask planes?
	wire [3:0] pixels0 = display[0] ? map_pixels[0][3:0] : 0;
	wire [3:0] pixels1 = display[1] ? map_pixels[1][3:0] : 0;

	// Compose the planes
	// ==================
	// Temporary code, probably want to redo the composition
	reg [3:0] temp_out;
	reg [1:0] depth_out_reg;
	//wire [3:0] next_out = pixels0 == '0 ? pixels1 : pixels0;

	//wire p0_2bpp = attr[0][0];
	wire p0_always_opaque;
	wire [3:0] p0_pal;
	assign {p0_pal, p0_always_opaque} = attr[0];
	wire p0_2bpp = p0_pal != '1;

	wire p0_opaque_4bpp = pixels0 != 0;
	wire p0_opaque_2bpp = scan_plane[0] ? (pixels0[3:2] != 0) : (pixels0[1:0] != 0);
	wire p0_opaque = (p0_2bpp ? p0_opaque_2bpp : p0_opaque_4bpp) | p0_always_opaque;
	wire top_plane = !p0_opaque;

	wire plane_odd = scan_plane[top_plane];
	wire [ATTR_BITS-1:0] top_attr = attr[top_plane];
	wire [3:0] top_pixels = top_plane == 1 ? pixels1 : pixels0;

	/*
	wire [1:0] pal;
	wire tile_2bpp;
	assign {pal, tile_2bpp} = top_attr[2:0];

	wire [COLOR_BITS-1:0] curr_color_2bpp_0 = plane_odd ? top_pixels[3:2] : top_pixels[1:0];
	wire [FULL_COLOR_BITS-1:0] curr_color_2bpp = {curr_color_2bpp_0 == 0 ? 2'b0 : pal, curr_color_2bpp_0};
	wire [FULL_COLOR_BITS-1:0] curr_color = tile_2bpp ? curr_color_2bpp : top_pixels;
	*/

	wire [3:0] pal;
	wire always_opaque;
	assign {pal, always_opaque} = top_attr;

	wire [3:0] curr_color;
	wire opaque;
	color_index_decoder index_decoder(
		.pixel_data(top_pixels), .pixel_index(plane_odd), .pal(pal), .always_opaque(always_opaque),
		.index(curr_color), .opaque(opaque) //, ._2bpp(_2bpp)
	);


	wire [3:0] next_out = curr_color;
	wire [1:0] next_depth = p0_opaque ? 0 : (opaque ? 1 : 2);


	always @(posedge clk) begin
		if (serial_counter == 3) begin
			temp_out <= next_out;
			depth_out_reg <= next_depth;
		end
	end
	assign pixel_out = temp_out;
	assign depth_out = depth_out_reg;
endmodule


module ditherer (
		input wire [2:0] u,
		input wire [1:0] dither,
		output wire [1:0] y
	);

	wire [3:0] x = (u < 2) ? {1'b0, u} : {(u - 3'd1), 1'b0};
	wire [3:0] x2 = x + {2'b0, dither};
	assign y = x2[3:2];
endmodule

module PPU #(
		parameter RAM_LOG2_CYCLES=2, RAM_PINS=4, X_BITS=9, Y_BITS=8, Y_SUB_BITS=1, ID_BITS=6, RAM_SYNC_STEP=3, DATA_DELAY=4,
		TILE_X_BITS=3, TILE_Y_BITS=3, MAP_X_BITS=6, MAP_Y_BITS=6,
		HPARAMS=`HPARAMS_320, VPARAMS=`VPARAMS_480, VPARAMS1=`VPARAMS_64_TEST, VPARAMS2=`VPARAMS_400, VPARAMS3=`VPARAMS_350
	) (
		input wire clk,
		input wire reset,

		output wire [ADDR_PINS-1:0] addr_pins,
		input wire [DATA_PINS-1:0] data_pins,

		output wire [3:0] pixel_out, // No longer used
		output wire [11:0] rgb_out,
		output wire [5:0] rgb_dithered_out,
		output wire active, hsync, vsync, // synced with rgb_out

		output wire new_frame, // high for one cycle, the frame begins at vblank

		output wire [`NUM_SCAN_FLAGS-1:0] scan_flags0,
		output reg [RAM_LOG2_CYCLES-1:0] serial_counter,
		output wire [X_BITS-1:0] x,
		output wire [Y_BITS-1:0] y
	);

	localparam Y_SCAN_BITS = Y_BITS + Y_SUB_BITS;

	localparam SYNC_DELAY = 1*4+2;
	localparam SYNC_DELAY_BITS = $clog2(SYNC_DELAY+1);

	localparam DATA_PINS = RAM_PINS;
	localparam ADDR_PINS = RAM_PINS;

	localparam X_CMP_BITS = X_BITS;
	localparam Y_CMP_BITS = Y_SCAN_BITS;


	genvar i;

	// reg [1:0] serial_counter;

	always @(posedge clk) begin
		if (reset) serial_counter <= 0;
		else serial_counter <= serial_counter + 1;
	end

	// Address output
	// ==============

	wire ram_enable = 1;

	wire new_transaction = serial_counter == 3;
	reg ram_on, ram_running;

	wire [ADDR_PINS-1:0] addr_out;
	reg [ADDR_PINS-1:0] addr_bits; // for combinational logic
	always_comb begin
		if (ram_running) addr_bits = addr_out;
		//else if (ram_on) addr_bits = (serial_counter == RAM_SYNC_STEP) ? 4'b1111 : 0; // sync on RAM_SYNC_STEP
		else if (ram_on) addr_bits = 4'b1 << serial_counter; // sync on one address bit each cycle
		else addr_bits = '0; // keep address bits low, ram is off
	end
	assign addr_pins = addr_bits;

	always @(posedge clk) begin
		if (reset) begin
			ram_running <= 0;
			ram_on <= 0;
		end else begin
			if (new_transaction) begin
				ram_running <= ram_on;
				ram_on <= ram_enable;
			end
		end
	end

	// VGA output
	// ==========

	// VGA timing
	// ----------

/*
	wire [X_BITS-1:0] x0_fp, xe_hsync, x0_bp, xe_active;
	wire [Y_SCAN_BITS-1:0] y1_active, y1_fp, y1_sync, y1_bp;

	assign {x0_fp, xe_hsync, x0_bp, xe_active} = HPARAMS;
	assign {y1_active, y1_fp, y1_sync, y1_bp} = VPARAMS;
*/

	// Sync delay
	// ----------

	wire [2:0] avhsync;
	reg [2:0] avhsync_delayed;
	reg [SYNC_DELAY_BITS-1:0] sync_delay;

	always @(posedge clk) begin
		if (reset || sync_delay == 0) avhsync_delayed <= avhsync;

		if (reset) begin
			sync_delay <= '1;
		end else if (sync_delay == '1) begin
			if (avhsync != avhsync_delayed) sync_delay <= SYNC_DELAY;
		end else begin
			sync_delay <= sync_delay - 1;
		end
	end

	// Raster scan
	// -----------

	wire [`NUM_SCAN_FLAGS-1:0] scan_flags;
	wire [X_CMP_BITS-1:0] x_cmp;
	wire [Y_CMP_BITS-1:0] y_cmp;
	wire y_frac;
	wire x_frac = serial_counter[1];
	raster_scan2 #(.X_BITS(X_BITS), .Y_BITS(Y_BITS), .Y_SUB_BITS(Y_SUB_BITS)) rs2(
		.clk(clk), .reset(reset), .enable(serial_counter == 3),
		.xe_active(xe_active), .x0_fp(x0_fp), .xe_hsync(xe_hsync), .x0_bp(x0_bp),
		.y1_active(y1_active), .y1_fp(y1_fp), .y1_sync(y1_sync), .y1_bp(y1_bp),

		.scan_flags0(scan_flags0), .scan_flags1(scan_flags),
		.x1(x), .y1(y), .y_lsb1(y_frac),
		.x_cmp(x_cmp), .y_cmp(y_cmp)
	);

	assign avhsync = {scan_flags[`I_ACTIVE], scan_flags[`I_VSYNC] ^ vsync_polarity, scan_flags[`I_HSYNC] ^ hsync_polarity};

	/*
	assign active = scan_flags[`I_ACTIVE];
	assign avhsync[0] = scan_flags[`I_HSYNC];
	assign avhsync[1] = scan_flags[`I_VSYNC];
	assign active_or_bp = scan_flags[`I_ACTIVE_OR_BP];
	assign new_line = scan_flags[`I_NEW_LINE];
	assign new_frame = scan_flags[`I_NEW_FRAME];
	assign last_pixel = scan_flags[`I_LAST_PIXEL];
	*/

	// Output
	// ------

	assign {active, vsync, hsync} = avhsync_delayed;

	// Rendering
	// =========

	// Final pixel composition. TODO: Put somewhere else
	wire [3:0] pixel_out_s, pixel_out_t;
	wire [1:0] depth_out_s, depth_out_t;
	//assign pixel_out = (pixel_out_s == 0 || !display_sprites) ? pixel_out_t : pixel_out_s;
	assign pixel_out = (depth_out_s > depth_out_t || !display_sprites) ? pixel_out_t : pixel_out_s;

	// Read coordinator
	// ----------------

	localparam NUM_LEVELS = 7; // Including the zero level
	localparam LOG2_NUM_LEVELS = $clog2(NUM_LEVELS);

	localparam SPRITE_UNIT_LEVEL  = 1; // 3 levels
	localparam COPPER_LEVEL       = 4; // 1 levels
	localparam TILEMAP_UNIT_LEVEL = 5; // Highest priority, 2 levels

	assign request_filtered[SPRITE_UNIT_LEVEL +3-1 -: 3] = (ram_running && sprite_tile_read_active && load_sprites) ? request[SPRITE_UNIT_LEVEL +3-1 -: 3] : '0;
	assign request_filtered[TILEMAP_UNIT_LEVEL+2-1 -: 2] = ram_running && sprite_tile_read_active ? request[TILEMAP_UNIT_LEVEL+2-1 -: 2] : '0;
	assign request_filtered[COPPER_LEVEL] = ram_running && request[COPPER_LEVEL];


	// Don't read sprite and tile data
	// * during vblank
	// * 4 pixels before hblank starts -- clear out levels_sreg from sprite transactions to prepare for restart
	wire sprite_tile_read_active = scan_flags0[`I_V_ACTIVE] && !scan_flags0[`I_LAST_PIXEL_GROUP];


	// Address mux. Must use the address from the highest priority granted.
	wire [ADDR_PINS-1:0] addr_out_s, addr_out_t, addr_out_c;
	wire req_tilemap = |request_filtered[TILEMAP_UNIT_LEVEL+2-1 -: 2];
	wire req_copper = request_filtered[COPPER_LEVEL];
	assign addr_out = req_tilemap ? addr_out_t : (req_copper ? addr_out_c : addr_out_s);


	wire [NUM_LEVELS-1:1] request, request_filtered;
	wire [LOG2_NUM_LEVELS-1:0] addr_level, data_level;
	wire [LOG2_NUM_LEVELS*DATA_DELAY-1:0] levels_sreg;

	read_coordinator #(.NUM_LEVELS(NUM_LEVELS), .DATA_DELAY(DATA_DELAY)) rcoord(
		.clk(clk), .reset(reset), .enable(serial_counter == 3),
		.request(request_filtered),
		.addr_level(addr_level), .data_level(data_level), .levels_sreg(levels_sreg)
	);

	// Palette
	// -------

	localparam PAL_SIZE = 16;
	localparam PAL_ADDR_BITS = $clog2(PAL_SIZE);
	localparam PAL_BITS = 8;
	localparam PAL_PIECE_BITS = 4;
	//localparam PAL_PIECES = PAL_BITS/PAL_PIECE_BITS;

	wire pal_wen;
	reg [PAL_BITS-1:0] pal[PAL_SIZE];
	reg [PAL_BITS-1:0] pal_temp; // Only PAL_BITS-PAL_PIECE_BITS used

	wire [PAL_BITS-1:0] pal_out = {pal_data_out, pal_temp[PAL_BITS-1:PAL_PIECE_BITS]};
	//wire [PAL_BITS-1:0] pal_out; assign pal_out[7:5] = pixel_out[0] << 2; assign pal_out[4:2] = pixel_out[2:1] << 1; assign pal_out[1:0] = pixel_out[3] << 1; // !!!

	reg [11:0] rgb_out_reg; // temporary output register. TODO: Better pixel composition


	// Apply dithering
	//assign rgb_out = rgb_out_reg;
	wire [1:0] dither = {x_frac ^ y_frac, y_frac};
	wire [3:0] r0_out, g0_out, b0_out;
	wire [1:0] r_out, g_out, b_out;
	assign {r0_out, g0_out, b0_out} = rgb_out_reg;
	ditherer dither_r(.u(r0_out[3:1]), .dither(dither), .y(r_out));
	ditherer dither_g(.u(g0_out[3:1]), .dither(dither), .y(g_out));
	ditherer dither_b(.u(b0_out[3:1]), .dither(dither), .y(b_out));

	//assign rgb_out = active ? {r_out, r_out, g_out, g_out, b_out, b_out} : '0;
	assign rgb_dithered_out = active ? {r_out, g_out, b_out} : '0;
	assign rgb_out = active ? rgb_out_reg : '0;


	always @(posedge clk) begin
		if (serial_counter == 3) begin
			rgb_out_reg[11:8] <= {pal_out[7:5], 1'b0}; // r
			rgb_out_reg[ 7:4] <= {pal_out[4:2], 1'b0}; // g
			rgb_out_reg[ 3:0] <= {pal_out[1:0], pal_out[5], 1'b0}; // b
		end
	end

	// Gate pal_raddr outside the active region to make it possibe for gate level tests to work.
	// Getting an X into pal_addr can make the entire palette contents into X.
	// (active || scan_flags[`I_ACTIVE]) is a slight overapproximation of the region where pal_raddr needs to be valid,
	// but seems to work ok for the GL tests.
	wire [PAL_ADDR_BITS-1:0] pal_raddr = (active || scan_flags[`I_ACTIVE]) ? pixel_out : '0;
	wire [PAL_ADDR_BITS-1:0] pal_waddr;
	//wire [PAL_ADDR_BITS-1:0] pal_addr = pal_wen ? pal_waddr : pal_raddr;

	// Make sure that pal_addr stays constant for two cycles at a time to avoid rotating palette entries.
	// TODO: Make sure that it does without this step.
	reg [PAL_ADDR_BITS-1:0] curr_pal_addr;
	always @(posedge clk) if (serial_counter[0] == 0) curr_pal_addr <= pal_addr;
	wire [PAL_ADDR_BITS-1:0] pal_addr = (serial_counter[0] == 1 ? curr_pal_addr : ((pal_wen && serial_counter[1]) ? pal_waddr : pal_raddr));


	wire [PAL_PIECE_BITS-1:0] pal_wdata;

	wire [PAL_PIECE_BITS-1:0] pal_data_out = pal[pal_addr][PAL_PIECE_BITS-1:0];
	wire [PAL_PIECE_BITS-1:0] pal_data_in = pal_wen ? pal_wdata : pal_data_out;
	always @(posedge clk) begin
		pal_temp <= {pal_data_out, pal_temp[PAL_BITS-1:PAL_PIECE_BITS]};
	end

	generate
		for (i=0; i < PAL_SIZE; i++) begin
			always @(posedge clk) begin
				if (i == pal_addr) pal[i] <= {pal_data_in, pal[i][PAL_BITS-1:PAL_PIECE_BITS]};
			end
		end
	endgenerate


	// Sprites
	// -------

	wire restart = scan_flags[`I_LAST_PIXEL];
	wire visible = scan_flags[`I_ACTIVE_OR_BP];
	//wire [X_BITS-1:0] x;
	//wire [Y_BITS-1:0] y;

	sprite_unit #(
		.ADDR_PINS(RAM_PINS), .DATA_PINS(RAM_PINS), .Y_BITS(Y_BITS), .ID_BITS(ID_BITS),
		.LOG2_NUM_LEVELS(LOG2_NUM_LEVELS), .BASE_LEVEL(SPRITE_UNIT_LEVEL)
	) sprite_buffer (
		.clk(clk), .reset(reset), .restart(restart), .visible(visible),
		.x(x), .y(y), .y_frac(y_frac),
		.serial_counter(serial_counter),
		.addr_pins(addr_out_s), .data_pins(data_pins),
		.temp_out(pixel_out_s), .depth_out(depth_out_s),
		.request(request[SPRITE_UNIT_LEVEL+3-1 -: 3]), .dt_in(addr_level), .dt_out(data_level), .dt_sreg(levels_sreg),
		.sorted_base_addr(sorted_base_addr), .oam_base_addr(oam_base_addr), .tile_base_addr(sprite_tile_base_addr)
	);

	// Tile map
	// --------

	// Don't load tile data unless active or just before (so that it will show up)
	// CONSIDER: Don't load tile data during the last 8 pixels, as it won't have time to show?
//	wire load_planes_scan = scan_flags0[`I_ACTIVE_OR_BP] && (x[X_BITS-1:TILE_X_BITS+1] >= ((128-2*2**TILE_X_BITS)>>(TILE_X_BITS+1)));
	wire load_planes_scan = scan_flags0[`I_ACTIVE_OR_BP] && ({3'd0, x[X_BITS-1:TILE_X_BITS+1]} >= ((128-2*2**TILE_X_BITS)>>(TILE_X_BITS+1)));

	// Assumes MAP_X_BITS+TILE_X_BITS >= MAP_Y_BITS+TILE_Y_BITS
	reg [MAP_X_BITS+TILE_X_BITS-1:0] scroll_regs[4];

	wire [MAP_X_BITS+TILE_X_BITS-1:0] scroll_x0 = scroll_regs[0];
	wire [MAP_Y_BITS+TILE_Y_BITS-1:0] scroll_y0 = scroll_regs[1];
	wire [MAP_X_BITS+TILE_X_BITS-1:0] scroll_x1 = scroll_regs[2];
	wire [MAP_Y_BITS+TILE_Y_BITS-1:0] scroll_y1 = scroll_regs[3];

	tilemap_unit #(
		.ADDR_PINS(RAM_PINS), .DATA_PINS(RAM_PINS), .X_BITS(X_BITS), .Y_BITS(Y_BITS),
		.MAP_X_BITS(MAP_X_BITS), .MAP_Y_BITS(MAP_Y_BITS), .TILE_X_BITS(TILE_X_BITS), .TILE_Y_BITS(TILE_Y_BITS),
		.LOG2_NUM_LEVELS(LOG2_NUM_LEVELS), .BASE_LEVEL(TILEMAP_UNIT_LEVEL)
	) tilemap (
		.clk(clk), .reset(reset),
		.load(load_planes_scan ? load_planes : 2'b00), .display(display_planes),
		.x(x), .y(y),
		.scroll_x0(scroll_x0), .scroll_y0(scroll_y0), .scroll_x1(scroll_x1), .scroll_y1(scroll_y1),
		.serial_counter(serial_counter),
		.addr_pins(addr_out_t), .data_pins(data_pins),
		.request(request[TILEMAP_UNIT_LEVEL+2-1 -: 2]), .dt_in(addr_level), .dt_out(data_level),
		.pixel_out(pixel_out_t), .depth_out(depth_out_t),
		.map_base_addr0(map_base_addr0), .map_base_addr1(map_base_addr1), .tile_base_addr(map_tile_base_addr)
	);

	// Copper
	// ======
	localparam REG_WDATA_BITS = 9;

	localparam REG_ADDR_BITS_FULL = 7;
	localparam REG_ADDR_BITS = 6; // Must be enough to include the stop code

	localparam NUM_BASE_ADDR_REGS = 4;
	localparam BASE_ADDR_REG_BITS = 9; // TODO: Suitable size? Max 9 bits

	localparam REG_ADDR_PAL    =       0; // Must be aligned to palette size, 16 registers right now
	localparam REG_ADDR_SCROLL =       16; // 4 registers
	localparam REG_ADDR_CMP    =       20; // 4 registers right now
	localparam REG_ADDR_BASE   =       24; // NUM_BASE_ADDR_REGS registers

	localparam REG_ADDR_GFXMODE1 = 28;
	localparam REG_ADDR_GFXMODE2 = 29;
	localparam REG_ADDR_GFXMODE3 = 30;
	// Don't make a register with address 2**REG_ADDR_BITS - 1; that is used to signal the stopping condition for the copper

	localparam REG_ADDR_DISPLAY_MASK = 31; // 1 register right now

	localparam REG_SUB_ADDR_BITS = 2;

	wire reg_wen;
	wire [REG_ADDR_BITS_FULL-1:0] reg_waddr_full;
	wire [REG_ADDR_BITS-1:0] reg_waddr = reg_waddr_full[REG_ADDR_BITS-1:0];
	wire [REG_SUB_ADDR_BITS-1:0] reg_sub_waddr = serial_counter;

	assign new_frame = scan_flags[`I_NEW_FRAME];
	wire [REG_WDATA_BITS-1:0] reg_wdata;
	copper #(
		.WADDR_BITS(REG_ADDR_BITS_FULL), .WADDR_BITS_USED(REG_ADDR_BITS), .WDATA_BITS(REG_WDATA_BITS),
		.DATA_DELAY(DATA_DELAY),
		.X_CMP_BITS(X_CMP_BITS), .Y_CMP_BITS(Y_CMP_BITS), .REG_ADDR_CMP(REG_ADDR_CMP),
		.LOG2_NUM_LEVELS(LOG2_NUM_LEVELS), .BASE_LEVEL(COPPER_LEVEL)
	) copper_inst(
		.clk(clk), .reset(reset), .restart(new_frame), // TODO: discard in-flight copper data when restarting
		.wen(reg_wen), .waddr(reg_waddr_full), .wdata(reg_wdata),
		.serial_counter(serial_counter),
		.addr_pins(addr_out_c), .data_pins(data_pins),
		.request(request[COPPER_LEVEL+1-1 -: 1]), .dt_in(addr_level), .dt_out(data_level), .dt_sreg(levels_sreg),
		.x_cmp(x_cmp), .y_cmp(y_cmp),
		.start_addr('hfffe)
	);

	// Write scroll registers
	generate
		for (i=0; i < 4; i++) begin
			always @(posedge clk) begin
				if (reg_wen && reg_waddr == REG_ADDR_SCROLL + i) begin
					/*
					if (reg_sub_waddr == 1) scroll_regs[i][0] <= reg_wdata[3];
					if (reg_sub_waddr == 2) scroll_regs[i][4:1] <= reg_wdata;
					if (reg_sub_waddr == 3) scroll_regs[i][8:5] <= reg_wdata;
					*/
					if (serial_counter == 3) scroll_regs[i] <= reg_wdata;
				end
			end
		end
	endgenerate

	// Base address registers
	wire [15:0] sorted_base_addr = {{(16-BASE_ADDR_REG_BITS-6){1'b0}}, base_addr_regs[0], 6'd0};
	wire [15:0] oam_base_addr    = {{(16-BASE_ADDR_REG_BITS-7){1'b0}}, base_addr_regs[1], 7'd0};

	wire [15:0] map_base_addr0        = {base_addr_regs[2][4:1], 12'd0};
	wire [15:0] map_base_addr1        = {base_addr_regs[2][8:5], 12'd0};

	wire [15:0] map_tile_base_addr    = {base_addr_regs[3][2:1], 14'd0};
	wire [15:0] sprite_tile_base_addr = {base_addr_regs[3][4:3], 14'd0};

	reg [BASE_ADDR_REG_BITS-1:0] base_addr_regs[NUM_BASE_ADDR_REGS];
	generate
		for (i=0; i < NUM_BASE_ADDR_REGS; i++) begin
			always @(posedge clk) begin
				if (reg_wen && reg_waddr == REG_ADDR_BASE + i) begin
					if (serial_counter == 3) base_addr_regs[i] <= reg_wdata[BASE_ADDR_REG_BITS-1:0];
				end
			end
		end
	endgenerate

	// Display mask register
	// TODO: Two display bits per plane if using two subscreens
	localparam DISPLAY_MASK_BITS = 6;
	reg [DISPLAY_MASK_BITS-1:0] display_mask;
	wire [1:0] display_planes, load_planes;
	wire display_sprites, load_sprites;
	assign {load_sprites, load_planes, display_sprites, display_planes} = display_mask;

	always @(posedge clk) begin
		if (reset) display_mask <= '1;
		else begin
			if (reg_wen && reg_waddr == REG_ADDR_DISPLAY_MASK && serial_counter == 3) display_mask <= reg_wdata[DISPLAY_MASK_BITS-1:0];
		end
	end

	// gfxmode registers
	reg [8:0] gfxmode1, gfxmode2, gfxmode3;

	wire [X_BITS-1:0] x0_fp_initial, xe_hsync_initial, x0_bp_initial, xe_active_initial;
	wire [X_BITS-1:0] x0_fp, xe_hsync, x0_bp, xe_active;
	wire [Y_SCAN_BITS-1:0] y1_active, y1_fp, y1_sync, y1_bp;

	assign {x0_fp_initial, xe_hsync_initial, x0_bp_initial, xe_active_initial} = HPARAMS;

	wire hsync_polarity, vsync_polarity; // 1 = negative

	assign x0_fp     = {6'd15, gfxmode1[2:0]};
	assign xe_hsync  = { 3'd2, gfxmode1[8:3]};
	assign x0_bp     = { 4'd3, gfxmode2[4:0]};
	wire [1:0] vparams_sel =   gfxmode2[6:5];
	assign {vsync_polarity, hsync_polarity} = gfxmode2[8:7];
	assign xe_active = gfxmode3;

	assign {y1_active, y1_fp, y1_sync, y1_bp} = vparams;

	// Not an actual register
	reg [Y_SCAN_BITS*4-1:0] vparams;
	always @(*) begin
		case (vparams_sel)
			0: vparams = VPARAMS;
			1: vparams = VPARAMS1;
			2: vparams = VPARAMS2;
			3: vparams = VPARAMS3;
		endcase
	end

	always @(posedge clk) begin
		if (reset) begin
			gfxmode1 <= {xe_hsync_initial[5:0], x0_fp_initial[2:0]};
			gfxmode2 <= {4'b1100, x0_bp_initial[4:0]}; // negative sync polarities, vparams_sel = 0
			gfxmode3 <= xe_active_initial;
		end else begin
			if (reg_wen && reg_waddr == REG_ADDR_GFXMODE1 && serial_counter == 3) gfxmode1 <= reg_wdata;
			if (reg_wen && reg_waddr == REG_ADDR_GFXMODE2 && serial_counter == 3) gfxmode2 <= reg_wdata;
			if (reg_wen && reg_waddr == REG_ADDR_GFXMODE3 && serial_counter == 3) gfxmode3 <= reg_wdata;
		end
	end

	//assign {x0_fp, xe_hsync, x0_bp, xe_active} = HPARAMS;
	//assign {y1_active, y1_fp, y1_sync, y1_bp} = VPARAMS;
	//wire hsync_polarity = 0, vsync_polarity = 0;


	/*
	reg [7:0] count; // Debug counter, not used
	always @(posedge clk) count <= count + new_frame;
	*/

	// Write palette
	assign pal_waddr = reg_waddr[PAL_ADDR_BITS-1:0];
	assign pal_wen = reg_wen && (reg_waddr[REG_ADDR_BITS-1:PAL_ADDR_BITS] == REG_ADDR_PAL >> PAL_ADDR_BITS) && (serial_counter[1]);
	assign pal_wdata = serial_counter[0] ? reg_wdata[8:5] : reg_wdata[4:1];
endmodule
