/*
 * Copyright (c) 2024 Toivo Henningsson <toivo.h.h@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module sbio_monitor #(parameter IO_BITS=2, SENS_BITS=2, COUNTER_BITS=5, INACTIVE_COUNTER_VALUE=31) (
		input wire clk, reset,

		input wire [IO_BITS-1:0] pins,

		output wire start, // Goes high when receving a start bit
		output wire active, // High during message except start bit
		output reg [COUNTER_BITS-1:0] counter, // INACTIVE_COUNTER_VALUE when inavtive and during start bit, then counts up
		input wire done // Put high during the the last cycle of the message
	);

	assign active = (counter != INACTIVE_COUNTER_VALUE);
	wire start_present = |pins[SENS_BITS-1:0];

	assign start = !active && start_present;
	wire reset_counter = (!active && !start_present) || done;

	wire [COUNTER_BITS-1:0] next_counter = reset_counter ? INACTIVE_COUNTER_VALUE : counter + {{(COUNTER_BITS-1){1'b0}}, 1'b1};

	always @(posedge clk) begin
		if (reset) begin
			counter <= INACTIVE_COUNTER_VALUE;
		end else begin
			counter <= next_counter;
		end
	end
endmodule : sbio_monitor


module context_switcher_test #(parameter IO_BITS=2, PAYLOAD_CYCLES=8, STATE_WORDS=9) (
		input wire clk, reset,

		input wire start_scan, // Don't raise while scanning
		output wire scan_done,

		output wire [IO_BITS-1:0] tx_pins,
		input wire [IO_BITS-1:0] rx_pins
	);

	localparam WORD_SIZE = PAYLOAD_CYCLES * IO_BITS;
	localparam STATE_BITS = WORD_SIZE * STATE_WORDS;

	localparam INDEX_BITS = $clog2(STATE_WORDS + 1); // One extra so that '1 can mean idle

	localparam SBIO_COUNTER_BITS = $clog2(PAYLOAD_CYCLES) + 1;


	genvar i, j;

	wire reading, writing;

	reg scanning_out;

	reg [INDEX_BITS-1:0] read_index_reg, write_index_reg;
	reg [STATE_BITS-1:0] state;
	wire [STATE_BITS-1:0] next_state, state_we; // if (state_we[i]) state[i] <= next_state[i]; state_we must be zero when scanning.

	wire [INDEX_BITS-1:0] next_read_index_reg  = read_index_reg  + tx_done_reading;
	wire [INDEX_BITS-1:0] next_write_index_reg = write_index_reg + rx_done_writing;

	wire scan_out_done = tx_done_reading && (read_index_reg  == STATE_WORDS - 1);
	assign scan_done   = rx_done_writing && (write_index_reg == STATE_WORDS - 1);

	wire [INDEX_BITS-1:0] read_index  = reading ? read_index_reg  : '1;
	wire [INDEX_BITS-1:0] write_index = writing ? write_index_reg : '1;

	wire [IO_BITS-1:0] scan_in;
	wire [IO_BITS-1:0] scan_outs[STATE_WORDS];
	wire [IO_BITS-1:0] scan_out = scan_outs[read_index_reg];

	// Context switching
	// -----------------
	always @(posedge clk) begin
		if (reset) begin
			scanning_out <= 0;
		end else begin
			if (start_scan) begin
				scanning_out <= 1;
				read_index_reg <= 0;
				write_index_reg <= 0;
			end else begin
				if (scan_out_done) scanning_out <= 0;
				read_index_reg  <= next_read_index_reg;
				write_index_reg <= next_write_index_reg;
			end
		end
	end

	// State update
	// ------------
	generate
		for (i=0; i < STATE_WORDS; i++) begin
			wire read_hit  = (i == read_index);
			wire write_hit = (i == write_index);
			wire scan_hit = read_hit || write_hit;

			// Ok with destructive read, don't need to recirculate when reading -- we will overwrite the read value with a new state
			wire [WORD_SIZE-1:0] next_state_scan = {scan_in, state[(i+1)*WORD_SIZE-1 -: (WORD_SIZE-IO_BITS)]};
			assign scan_outs[i] = state[i*WORD_SIZE+IO_BITS-1 -: IO_BITS];

			for (j=0; j < WORD_SIZE; j++) begin
				always @(posedge clk) begin
					if (scan_hit || state_we[i*WORD_SIZE + j]) state[i*WORD_SIZE + j] <= scan_hit ? next_state_scan[j] : next_state[i*WORD_SIZE + j];
				end
			end
		end
	endgenerate

	// TX
	// --
	wire tx_active; //, tx_started;
	wire [SBIO_COUNTER_BITS-1:0] tx_counter;
	wire tx_done;
	sbio_monitor #(.IO_BITS(IO_BITS), .SENS_BITS(1), .COUNTER_BITS(SBIO_COUNTER_BITS), .INACTIVE_COUNTER_VALUE(2**SBIO_COUNTER_BITS-2)) sbio_tx (
		.clk(clk), .reset(reset),
		.pins(tx_pins),
		//.start(tx_started), // Not needed, we should know when we start it
		.active(tx_active), .done(tx_done), .counter(tx_counter)
	);

	// TODO: Prioritize between traffic sources
	// TODO: Limit number of outstanding (unanswered) transactions
	wire tx_start = scanning_out && !tx_active;
	wire tx_state = (tx_counter[SBIO_COUNTER_BITS-1] == 0); // High if transmitting state. Low during start bits and header.
	assign reading = tx_state;
	assign tx_pins = tx_state ? scan_out : (tx_start ? 1 : 0); // Makes header = 2'd0
	assign tx_done = (tx_counter == PAYLOAD_CYCLES - 1);
	wire tx_done_reading = tx_done; // For now. TODO: Change when we can send other kinds of messages

	// RX
	// --
	wire rx_started, rx_active;
	wire [SBIO_COUNTER_BITS-1:0] rx_counter;
	wire rx_done;
	sbio_monitor #(.IO_BITS(IO_BITS), .SENS_BITS(2), .COUNTER_BITS(SBIO_COUNTER_BITS), .INACTIVE_COUNTER_VALUE(2**SBIO_COUNTER_BITS-1)) sbio_rx (
		.clk(clk), .reset(reset),
		.pins(rx_pins),
		.start(rx_started), .active(rx_active), .done(rx_done), .counter(rx_counter)
	);

	reg [IO_BITS-1:0] rx_sbs; // Start bits from last start
	always @(posedge clk) begin
		if (rx_started) rx_sbs <= rx_pins;
	end
	// Require start bits = 2'd1 to recognize context switch message
	wire rx_mode_state = (rx_sbs == 2'd1);
	wire rx_state = rx_mode_state && (rx_counter[SBIO_COUNTER_BITS-1] == 0); // High if receiving state. Low during start bits and header.
	assign writing = rx_state;
	assign scan_in = rx_pins;
	// Assumes that all messages have length described by PAYLOAD_CYCLES
	assign rx_done = (rx_counter == PAYLOAD_CYCLES - 1);
	wire rx_done_writing = rx_done && rx_mode_state;
endmodule : context_switcher_test

module context_keeper #(parameter IO_BITS=2, PAYLOAD_CYCLES=8, STATE_WORDS=3*9, FULL_STATE_WORDS=4*9, MEM_ADDR_BITS=5) (
		input wire clk, reset,

		output wire [IO_BITS-1:0] tx_pins,
		input wire [IO_BITS-1:0] rx_pins
	);

	localparam WORD_SIZE = PAYLOAD_CYCLES * IO_BITS;

	localparam INDEX_BITS = $clog2(FULL_STATE_WORDS);

	localparam SBIO_COUNTER_BITS = $clog2(PAYLOAD_CYCLES) + 1;


	reg [INDEX_BITS-1:0] state_index;
	reg [WORD_SIZE-1:0] state[FULL_STATE_WORDS];

	reg [WORD_SIZE-1:0] mem[2**MEM_ADDR_BITS];

	reg [WORD_SIZE-1:0] out;


	// RX
	// --
	wire rx_started, rx_active;
	wire [SBIO_COUNTER_BITS-1:0] rx_counter;
	wire rx_done;
	sbio_monitor #(.IO_BITS(IO_BITS), .SENS_BITS(1), .COUNTER_BITS(SBIO_COUNTER_BITS), .INACTIVE_COUNTER_VALUE(2**SBIO_COUNTER_BITS-2)) sbio_rx (
		.clk(clk), .reset(reset),
		.pins(rx_pins),
		.start(rx_started), .active(rx_active), .done(rx_done), .counter(rx_counter)
	);

	reg [WORD_SIZE-1:0] rx_buffer;
	reg rx_buffer_valid; // only high for one cycle
	// reg rx_buffer_type;

	reg [IO_BITS-1:0] rx_header;
	wire rx_mode_state = (rx_header == `TX_SOURCE_SCAN);
	wire rx_payload = (rx_counter[SBIO_COUNTER_BITS-1] == 0);
	assign rx_done = (rx_counter == PAYLOAD_CYCLES - 1);
	wire rx_done_state = rx_done && rx_mode_state;
	wire rx_buffer_valid_state = rx_buffer_valid && rx_mode_state;
	wire rx_buffer_valid_out  = rx_buffer_valid && (rx_header == `TX_SOURCE_OUT);
	wire rx_buffer_valid_addr = rx_buffer_valid && (rx_header == `TX_SOURCE_READ);

	always @(posedge clk) begin
		if (reset) begin
			rx_buffer_valid <= 0;
			tx_buffer_valid <= 0;
			//state_index <= 0;
			state_index <= STATE_WORDS; // Deliver the last context in state first, only once
		end else begin
			rx_buffer_valid <= rx_done;
		end

		if (rx_counter == '1) rx_header <= rx_pins;
		if (rx_payload) rx_buffer <= {rx_pins, rx_buffer[WORD_SIZE-1:IO_BITS]};

		if (rx_buffer_valid_state) begin
			tx_buffer <= {state[state_index], `RX_SB_SCAN}; // include start bits
			tx_buffer_valid <= 1;
			state[state_index] <= rx_buffer;
			state_index <= (state_index == STATE_WORDS - 1 || state_index == FULL_STATE_WORDS - 1) ? 0 : state_index + 1;
		end else if (rx_buffer_valid_addr) begin
			tx_buffer <= {mem[rx_buffer], `RX_SB_READ}; // include start bits
			tx_buffer_valid <= 1;
		end else if (rx_buffer_valid_out) begin
			// Refill sample credits when receiving a sample
			tx_buffer <= {`REG_ADDR_SAMPLE_CREDITS, 8'd3, `RX_SB_WRITE}; // include start bits
			tx_buffer_valid <= 1;
		end else if (tx_buffer_valid) begin
			tx_buffer <= tx_buffer[TX_BITS-1:IO_BITS];
			if (tx_done) tx_buffer_valid <= 0;
		end

		if (rx_buffer_valid_out) out <= rx_buffer;
	end

	// TX
	// --
	localparam TX_BITS = WORD_SIZE + IO_BITS;

	wire tx_active; //, tx_started;
	wire [SBIO_COUNTER_BITS-1:0] tx_counter;
	wire tx_done;
	sbio_monitor #(.IO_BITS(IO_BITS), .SENS_BITS(2), .COUNTER_BITS(SBIO_COUNTER_BITS), .INACTIVE_COUNTER_VALUE(2**SBIO_COUNTER_BITS-1)) sbio_tx (
		.clk(clk), .reset(reset),
		.pins(tx_pins),
		//.start(tx_started), // Not needed, we should know when we start it
		.active(tx_active), .done(tx_done), .counter(tx_counter)
	);

	reg [TX_BITS-1:0] tx_buffer;
	reg tx_buffer_valid;

	assign tx_pins = tx_buffer_valid ? tx_buffer[IO_BITS-1:0] : 0;
	assign tx_done = (tx_counter == PAYLOAD_CYCLES);
endmodule : context_keeper
