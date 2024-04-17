/*
 * Copyright (c) 2024 Toivo Henningsson <toivo.h.h@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`include "synth_common.vh"

module fir_table48 #( parameter I_COEFF_BITS = 6, I_TERM_BITS = 3, EXP_BITS = 4 ) (
		input wire [I_COEFF_BITS-1:0] i_coeff,
		input wire [I_TERM_BITS-1:0] i_term,

		output wire [I_TERM_BITS-1:0] last_term_index,
		output wire term_sign,
		output wire [EXP_BITS-1:0] term_exp
	);

	// Not actual registers
	reg [I_TERM_BITS-1:0] last;
	reg sign;
	reg [EXP_BITS-1:0] exp;
	always @(*) begin
		last = 'X;
		sign = 'X;
		exp = 'X;
`include "fir-coeffs-generated-48.vh"
	end
	assign last_term_index = last;
	assign term_sign = sign;
	assign term_exp = exp;
endmodule

`define TARGET_BITS 2
`define TARGET_NONE 2'd0
`define TARGET_ACC  2'd1
`define TARGET_Y    2'd2
`define TARGET_V    2'd3

`define A_SEL_BITS 2
`define A_SEL_ZERO 2'd0
`define A_SEL_ACC  2'd1
`define A_SEL_Y    2'd2
`define A_SEL_V    2'd3

`define B_SEL_BITS 2
`define B_SEL_WAVE 2'd1
`define B_SEL_Y    2'd2
`define B_SEL_V    2'd3

`define MOD_SEL_BITS 2
`define MOD_SEL_CUTOFF 2'd0
`define MOD_SEL_DAMP   2'd1
`define MOD_SEL_VOL    2'd2
`define MOD_SEL_FIR    2'd3

// Input injection into enabled y is enabled if topology[0] == 1
`define TOPOLOGY_SVF2           2'd0
`define TOPOLOGY_SVF2_TRANSPOSE 2'd1
`define TOPOLOGY_SVF2_2VOL      2'd2
`define TOPOLOGY_2X_LPF1        2'd3

module SVF_controller (
		input wire [`SVF_STEP_BITS-1:0] step,
		input wire [1:0] topology,
		input wire [1:0] wf_index,
		input wire bpf_en,
		input wire en,

		output reg [`A_SEL_BITS-1:0] a_sel,
		output reg [`B_SEL_BITS-1:0] b_sel,
		output reg [`MOD_SEL_BITS-1:0] mod_sel,
		output reg b_sign, we, target_v
	);

	wire _bpf_en = bpf_en && topology[0];

	always @(*) begin
		we = 0;
		a_sel = 'X;
		b_sel = 'X;
		mod_sel = 'X;
		b_sign = 1'bX;
		target_v = 1'bX;

		if (step == 2'd1) begin
			if (_bpf_en) begin // y -= a_vol * u // step 1: input (must be run after step 2)
				target_v = 0; we = en;
				a_sel = `A_SEL_Y;
				b_sel = `B_SEL_WAVE; b_sign = 1; // TODO: best sign?
			end else begin // v += a_vol * u0_lpf // step 1: input (if input to y, must be run after step 2)
				target_v = 1; we = en;
				a_sel = `A_SEL_V;
				b_sel = `B_SEL_WAVE; b_sign = 0;
			end
			mod_sel = (topology == `TOPOLOGY_SVF2_2VOL && wf_index[0]) ? `MOD_SEL_DAMP : `MOD_SEL_VOL;
		end else case (topology)
			`TOPOLOGY_SVF2: case (step) // Non-transposed resonant filter
				2'd0: begin // v -= a_damp * v // step 0: can't change y
					target_v = 1; we = en;
					a_sel = `A_SEL_V;
					b_sel = `B_SEL_V; b_sign = 1; mod_sel = `MOD_SEL_DAMP;
				end
				2'd2: begin // v -= a_cutoff * y   // step 2
					target_v = 1; we = en;
					a_sel = `A_SEL_V;
					b_sel = `B_SEL_Y; b_sign = 1; mod_sel = `MOD_SEL_CUTOFF;
				end
				2'd3: begin // y += a_cutoff * v   // step 3: produces output in y
					target_v = 0; we = en;
					a_sel = `A_SEL_Y;
					b_sel = `B_SEL_V; b_sign = 0; mod_sel = `MOD_SEL_CUTOFF;
				end
			endcase
			`TOPOLOGY_SVF2_TRANSPOSE: case (step) // Transposed resonant filter
				2'd0: begin // v -= a_cutoff * y   // step 0: can't change y
					target_v = 1; we = en;
					a_sel = `A_SEL_V;
					b_sel = `B_SEL_Y; b_sign = 1; mod_sel = `MOD_SEL_CUTOFF;
				end
				2'd2: begin // y -= a_damp * y // step 2
					target_v = 0; we = en;
					a_sel = `A_SEL_Y;
					b_sel = `B_SEL_Y; b_sign = 1; mod_sel = `MOD_SEL_DAMP;
				end
				2'd3: begin // y += a_cutoff * v   // step 3: produces output in y
					target_v = 0; we = en;
					a_sel = `A_SEL_Y;
					b_sel = `B_SEL_V; b_sign = 0; mod_sel = `MOD_SEL_CUTOFF;
				end
			endcase
			`TOPOLOGY_SVF2_2VOL: case (step) // Non-transposed resonant filter with 2 volumes instead of resonance
				2'd0: begin // v -= a_cutoff * v // step 0: can't change y
					target_v = 1; we = en;
					a_sel = `A_SEL_V;
					b_sel = `B_SEL_V; b_sign = 1; mod_sel = `MOD_SEL_CUTOFF;
				end
				2'd2: begin // v -= a_cutoff * y   // step 2
					target_v = 1; we = en;
					a_sel = `A_SEL_V;
					b_sel = `B_SEL_Y; b_sign = 1; mod_sel = `MOD_SEL_CUTOFF;
				end
				2'd3: begin // y += a_cutoff * v   // step 3: produces output in y
					target_v = 0; we = en;
					a_sel = `A_SEL_Y;
					b_sel = `B_SEL_V; b_sign = 0; mod_sel = `MOD_SEL_CUTOFF;
				end
			endcase
			`TOPOLOGY_2X_LPF1: case (step) // Dual lpf1 filter
				2'd0: begin // v -= a_cutoff * v // step 0: can't change y
					target_v = 1; we = en;
					a_sel = `A_SEL_V;
					b_sel = `B_SEL_V; b_sign = 1; mod_sel = `MOD_SEL_CUTOFF;
				end
				2'd2: begin // y -= a_damp * y   // step 2
					target_v = 0; we = en;
					a_sel = `A_SEL_Y;
					b_sel = `B_SEL_Y; b_sign = 1; mod_sel = `MOD_SEL_DAMP;
				end
				2'd3: begin // y += a_damp * v   // step 3: produces output in y
					target_v = 0; we = en;
					a_sel = `A_SEL_Y;
					b_sel = `B_SEL_V; b_sign = 0; mod_sel = `MOD_SEL_DAMP;
				end
			endcase
		endcase
	end
endmodule : SVF_controller

module subsamp_voice #(
		parameter PHASE_BITS = 10, OCT_BITS = 4, SUPERSAMP_BITS = 2, SUBSAMP_BITS = 3, FIR_OUT_TAPS = 3, MAX_TERMS_PER_COEFF = 8, NUM_ACCS = 3, ACC_BITS = 20,
		NUM_OSCS = 2, MOD_MANTISSA_BITS = 6, NUM_MODS = 3, LFSR_BITS = 15,
		IO_BITS=2, PAYLOAD_CYCLES=8, STATE_WORDS=`STATE_WORDS,
		NUM_SWEEPS = 5, SWEEP_MANTISSA_BITS = 6
	) (
		input wire clk, reset,

		input wire new_sample, step_sample, ext_scan_accs, rewind_out_sample, inc_sweep_oct_counter, // ext_scan_accs should be low during fir_enable
		// assumes scan, osc_enable and fir_enable are mutually exclusive
		input wire [NUM_OSCS-1:0] osc_enable, 
		input wire fir_enable,
		output wire fir_done,
		output wire sample_done, // can go high at osc_enable
		output wire fir_prepare, // goes high when fir_enable and FIR filter is not using the shift adder
		output wire [$clog2(FIR_OUT_TAPS)-1:0] tap_pos,

		input wire svf_enable,
		input wire [`SVF_STEP_BITS-1:0] svf_step,
		input wire [`LOG2_NUM_WFS-1:0] wf_index,

		output wire out_valid, // new sample when high; out must be sampled on that cycle. Assumed to be high for only one cycle
		output wire signed [PAYLOAD_CYCLES*IO_BITS-1:0] out,

		input wire context_switch,
		input wire [$clog2(STATE_WORDS + 1)-1:0] read_index, write_index,
		input wire [IO_BITS-1:0] scan_in,
		output wire [IO_BITS-1:0] scan_out,

		input wire [PAYLOAD_CYCLES*IO_BITS-1:0] rx_buffer,
		input wire sweep_data_valid,
		input wire [$clog2(NUM_SWEEPS)-1:0] sweep_index
	);

	localparam SAMP_BITS = SUPERSAMP_BITS + SUBSAMP_BITS;
	localparam STEP_EXP_BITS = $clog2(SUBSAMP_BITS + 1);
	localparam FP_BITS  = OCT_BITS + PHASE_BITS;
	localparam MOD_BITS = OCT_BITS + MOD_MANTISSA_BITS;
	localparam SWEEP_BITS = OCT_BITS + SWEEP_MANTISSA_BITS;

	localparam DIVIDER_BITS = 2**OCT_BITS - SUBSAMP_BITS; // TODO: correct?
	localparam SWEEP_DIVIDER_BITS = 2**OCT_BITS - 1; // TODO: correct?

	localparam SHIFTADD_BITS = ACC_BITS;
	localparam SVF_STATE_BITS = SHIFTADD_BITS;

	localparam WORD_SIZE = PAYLOAD_CYCLES * IO_BITS;
	localparam STATE_BITS = WORD_SIZE * STATE_WORDS;

	localparam INDEX_BITS = $clog2(STATE_WORDS + 1); // One extra so that '1 can mean idle

	localparam NUM_WFS = 3;


	genvar i, j;

	wire main_osc_enable = osc_enable[0];

	// Oscillator
	// ==========

	reg [DIVIDER_BITS-1:0] oct_counter;
	reg [SWEEP_DIVIDER_BITS-1:0] sweep_oct_counter;
	// Increase only when advancing by a FIR input step and only for the main oscillator. Rewind as appropriate.
	// CONSIDER: use internal carry from next_fir_offset
	wire oct_counter_forward = (next_fir_offset[SAMP_BITS-1:SUBSAMP_BITS] != fir_offset[SAMP_BITS-1:SUBSAMP_BITS]);
	wire oct_counter_we = oct_counter_forward || rewind_out_sample;
	// rewind_out_sample=1 messes with oct_enables, but it's only on during context switching, when oct_enables is not needed
	wire [DIVIDER_BITS-1:0] oct_counter_step = rewind_out_sample ? (-1 << SUPERSAMP_BITS) : 1;

	wire [DIVIDER_BITS-1:0] next_oct_counter = oct_counter + oct_counter_step;
	wire [DIVIDER_BITS+SUBSAMP_BITS:0] oct_enables;
	assign oct_enables[SUBSAMP_BITS:0] = '1;
	assign oct_enables[DIVIDER_BITS+SUBSAMP_BITS:SUBSAMP_BITS+1] = next_oct_counter & ~oct_counter; // Could optimize oct_enables[1] to just next_oct_counter[0]

	wire [SWEEP_DIVIDER_BITS-1:0] next_sweep_oct_counter = sweep_oct_counter + 1;
	wire [SWEEP_DIVIDER_BITS:0] sweep_oct_enables;
	assign sweep_oct_enables[0] = '1;
	wire [SWEEP_DIVIDER_BITS-1:0] swoe = next_sweep_oct_counter & ~sweep_oct_counter;
	assign sweep_oct_enables[SWEEP_DIVIDER_BITS-1:1] = swoe[SWEEP_DIVIDER_BITS-2:0]; // Could optimize sweep_oct_enables[1] to just next_sweep_oct_counter[0]
	assign sweep_oct_enables[SWEEP_DIVIDER_BITS] = 0;

	// Create osc_oct_enables with msb always zero.
	// CONSIDER: Turn off lowest octave using explicit compare oct == 2**OCT_BITS-1 instead, if oct scale differs between oscillators.
	wire [2**OCT_BITS-1:0] osc_oct_enables;
	assign osc_oct_enables[2**OCT_BITS-2:0] = oct_enables[2**OCT_BITS-2:0];
	assign osc_oct_enables[2**OCT_BITS-1] = 0; // Make slowest octave = oscillator off. TODO: can sub-oscillator be slow enough?

	wire step_enable = (osc_enable != '0) && osc_oct_enables[oct];

	// NB: Only works for up to two oscillators. But we're not expecting to use more.
	wire osc_index = osc_enable[1];

	reg [PHASE_BITS-1:0] d_phase[NUM_OSCS];
	reg [NUM_OSCS-1:0] d_delayed_p = 0;
	reg d_delayed_s = 0;
	reg [FP_BITS-1:0] d_float_period[NUM_OSCS];

	wire [PHASE_BITS-1:0] curr_phase = phase[osc_index];
	wire curr_delayed_p = delayed_p[osc_index];
	wire [FP_BITS-1:0] curr_float_period = float_period[osc_index];

	wire [PHASE_BITS-1:0] mantissa;
	wire [OCT_BITS-1:0] oct;
	assign {oct, mantissa} = curr_float_period;


	wire [OCT_BITS+1-1:0] step_exp0 = SUBSAMP_BITS - oct;
	wire [STEP_EXP_BITS-1:0] step_exp = step_exp0[OCT_BITS] ? 0 : step_exp0[STEP_EXP_BITS-1:0];
	wire [SUBSAMP_BITS-1:0] step_mask = ((2**SUBSAMP_BITS - 1) << step_exp) >> SUBSAMP_BITS; // CONSIDER: Better way to compute?
	//wire [SUBSAMP_BITS:0] phase_step = 1 << step_exp; // CONSIDER: Better way to compute?
	wire [SUBSAMP_BITS:0] phase_step = {step_mask, 1'b1} & ~{1'b0, step_mask};


	wire [PHASE_BITS-1:0] rev_phase0;
	generate
		for (i = 0; i < PHASE_BITS; i++) assign rev_phase0[i] = curr_phase[PHASE_BITS - 1 - i];
	endgenerate
	wire [PHASE_BITS-1:0] rev_phase = rev_phase0 << step_exp;

	wire update_phase = !(curr_delayed_p || delayed_s) && step_enable;
	//wire [PHASE_BITS-1:0] phase_inc = (update_phase ? phase_step : 0);
	wire [PHASE_BITS-1:0] phase_inc = {{(PHASE_BITS-(SUBSAMP_BITS+1)){1'b0}}, phase_step};
	//wire sum_phases = !(|osc_enable);
	wire wave_we = svf_we && (svf_step == 1);
	//wire [PHASE_BITS-1:0] phase_term = sum_phases ? (invert_phase1 ? ~phase[1] : phase[1]) : phase_inc;
	//wire [PHASE_BITS-1:0] phase_sum = curr_phase + phase_term;
	wire [PHASE_BITS-1:0] phase_term1 = phase_inc;
	wire [PHASE_BITS-1:0] phase_term2 = invert_phase1 ? ~phase[1] : phase[1];
	wire [PHASE_BITS-1:0] phase_sum1 = curr_phase + phase_term1;
	//wire [PHASE_BITS-1:0] phase_sum2 = (phase[0] << phase0_shl) + (phase_term2 << phase1_shl);
	wire [PHASE_BITS-1:0] phase_sum2 = ((pass_phase0 ? phase[0] : 0) << phase0_shl) + ((pass_phase1 ? phase_term2 : 0) << phase1_shl);

	reg signed [WAVE_BITS-1:0] wave_reg;

	// Split mantissa
	wire [PHASE_BITS-1:0] mantissa_p;
	assign mantissa_p[SUBSAMP_BITS-1:0] = mantissa[SUBSAMP_BITS-1:0] & ~step_mask;
	assign mantissa_p[PHASE_BITS-1:SUBSAMP_BITS] = mantissa[PHASE_BITS-1:SUBSAMP_BITS];
	wire [SUBSAMP_BITS-1:0] mantissa_sub = mantissa[SUBSAMP_BITS-1:0] & step_mask;

	wire next_delayed_p = mantissa_p > rev_phase;
	wire next_delayed_s = {{(PHASE_BITS-2*SUBSAMP_BITS){1'b0}}, mantissa_sub, {SUBSAMP_BITS{1'b0}}} > rev_phase; // CONSIDER: simplify logic for mantissa_sub comparison

	// valid when osc_enable[0] is high
	wire phase_rollover = phase[0][PHASE_BITS-1] && !phase_sum1[PHASE_BITS-1];

	// LFSR
	// ----
	wire [PHASE_BITS-1:0] lfsr_base_next;
	wire [LFSR_EXTRA_BITS-1:0] lfsr_extra_next;

	assign {lfsr_extra_next, lfsr_base_next} = lfsr_next;
	wire [LFSR_BITS-1:0] lfsr = {lfsr_extra, phase[1]};

	wire [LFSR_BITS-1:0] lfsr_next = {lfsr[13:0], (lfsr[0] ^ lfsr[14]) | (lfsr == 0)};

	// Oscillator update including LFSR
	// --------------------------------
	wire lfsr_active = params[PARAM_BIT_LFSR] && osc_enable[1];

	wire [PHASE_BITS-1:0] phase_next = lfsr_active ? lfsr_base_next : phase_sum1;
	// phase1 is only written when phase_we[0] for hardsync
	wire [PHASE_BITS-1:0] phase1_next = phase_we[0] ? {hardsync_phase, {(PHASE_BITS-RESET_PHASE_BITS){1'b0}}} : phase_next;
	assign lfsr_extra_we = lfsr_active && update_phase;

	// State updates
	// -------------

	// Not actually registers
	reg delayed_s_we, running_counter_we, y_we, v_we;
	reg [NUM_OSCS-1:0] delayed_p_we; // One per bit!
	reg [NUM_OSCS-1:0] phase_we;
	wire lfsr_extra_we;
	wire [NUM_OSCS-1:0] fp_we;
	wire [NUM_MODS-1:0] mod_we;
	wire ringmod_state_we = wave_we;

	reg delayed_s_next;
	reg [NUM_OSCS-1:0] delayed_p_next;
	wire [MOD_MANTISSA_BITS-1:0] running_counter_next = phase_rollover ? 0 : running_counter + {{(MOD_MANTISSA_BITS-1){1'b0}}, !delayed_s};
	wire [SVF_STATE_BITS-1:0] yv_next = shift_sum;
	wire [FP_BITS-1:0] fp_next;
	wire [MOD_BITS-1:0] mod_next;
	wire ringmod_state_next = wave[WAVE_BITS-1] && ringmod;
	always @(*) begin
		delayed_s_we = 0;
		delayed_p_we = 0;
		phase_we = 0;
		running_counter_we = 0;
		y_we = 0;
		v_we = 0;

		delayed_s_next = 'X;
		delayed_p_next = 'X;

		if (!context_switch) begin
			if (step_enable) begin
				if (delayed_s) begin
					// Don't update delayed_s except for main oscillator
					if (main_osc_enable) begin; delayed_s_next = 0; delayed_s_we = 1; end // delayed_s <= 0;
				end else if (curr_delayed_p) begin
					if (osc_enable[0]) begin delayed_p_next[0] = 0; delayed_p_we[0] = 1; end // delayed_p[0] <= 0;
					if (osc_enable[1]) begin delayed_p_next[1] = 0; delayed_p_we[1] = 1; end // delayed_p[1] <= 0;
				end else begin
					if (osc_enable[0]) begin delayed_p_next[0] = next_delayed_p; delayed_p_we[0] = 1; end // delayed_p[0] <= next_delayed_p;
					if (osc_enable[1]) begin delayed_p_next[1] = next_delayed_p; delayed_p_we[1] = 1; end // delayed_p[1] <= next_delayed_p;
					// Don't update delayed_s except for main oscillator
					if (main_osc_enable) begin; delayed_s_next = next_delayed_s; delayed_s_we = 1; end // delayed_s <= next_delayed_s;
				end
			end
			//fir_offset <= next_fir_offset;

			if (osc_enable[0]) phase_we[0] = update_phase; // phase[0] <= phase_sum1;
			if (osc_enable[1]) phase_we[1] = update_phase; // phase[1] <= phase_sum1;
			if (osc_enable[0]) running_counter_we = 1; // running_counter <= phase_rollover ? 0 : running_counter + !delayed_s;

			// Hard sync, since phase_we[0] is set, phase1_next is modified for reset
			if (osc_enable[0] && update_phase && hardsync && phase_rollover) phase_we[1] = 1'b1;

			if (target_reg == `TARGET_Y) y_we = 1;
			if (target_reg == `TARGET_V) v_we = 1;
		end
	end

	// State register
	// --------------
	localparam DELAYED_S_TOP = 0 + 1;
	wire delayed_s = state[DELAYED_S_TOP-1 -: 1];

	localparam DELAYED_P_TOP = DELAYED_S_TOP + NUM_OSCS;
	wire [NUM_OSCS-1:0] delayed_p = state[DELAYED_P_TOP-1 -: NUM_OSCS];

	localparam FIR_OFFSET_TOP = DELAYED_P_TOP + SUBSAMP_BITS;
	wire [SAMP_BITS-1:0] fir_offset = {fir_offset_msbs, state[FIR_OFFSET_TOP-1 -: SUBSAMP_BITS]};

	localparam PHASE0_TOP = FIR_OFFSET_TOP + PHASE_BITS;
	localparam PHASE1_TOP = PHASE0_TOP + PHASE_BITS;
	wire [PHASE_BITS-1:0] phase[NUM_OSCS];
	assign phase[0] = state[PHASE0_TOP-1 -: PHASE_BITS];
	assign phase[1] = state[PHASE1_TOP-1 -: PHASE_BITS];

	localparam RC_TOP = PHASE1_TOP + MOD_MANTISSA_BITS;
	wire [MOD_MANTISSA_BITS-1:0] running_counter = state[RC_TOP-1 -: MOD_MANTISSA_BITS];

	localparam Y_TOP = RC_TOP + SVF_STATE_BITS;
	localparam V_TOP = Y_TOP + SVF_STATE_BITS;
	wire [SVF_STATE_BITS-1:0] y = state[Y_TOP-1 -: SVF_STATE_BITS];
	wire [SVF_STATE_BITS-1:0] v = state[V_TOP-1 -: SVF_STATE_BITS];

	localparam FP0_TOP = V_TOP + FP_BITS;
	localparam FP1_TOP = FP0_TOP + FP_BITS;
	wire [FP_BITS-1:0] float_period[NUM_OSCS];
	assign float_period[0] = state[FP0_TOP-1 -: FP_BITS];
	assign float_period[1] = state[FP1_TOP-1 -: FP_BITS];

	localparam MOD0_TOP = FP1_TOP + MOD_BITS;
	localparam MOD1_TOP = MOD0_TOP + MOD_BITS;
	localparam MOD2_TOP = MOD1_TOP + MOD_BITS;
	localparam MODLAST_TOP = FP1_TOP + MOD_BITS*NUM_MODS;
	wire [MOD_BITS-1:0] mods[NUM_MODS];
	generate
		for (i=0; i < NUM_MODS; i++) begin
			assign mods[i] = state[MOD0_TOP-1 + i*MOD_BITS -: MOD_BITS];
		end
	endgenerate

	localparam LFSR_EXTRA_BITS = LFSR_BITS - PHASE_BITS;
	localparam LFSR_EXTRA_TOP = MODLAST_TOP + LFSR_EXTRA_BITS;
	wire [LFSR_EXTRA_BITS-1:0] lfsr_extra = state[LFSR_EXTRA_TOP-1 -: LFSR_EXTRA_BITS];
	reg [LFSR_EXTRA_BITS-1:0] d_lfsr_extra = 0;

	localparam RINGMOD_STATE_TOP = LFSR_EXTRA_TOP + 1;
	wire ringmod_state = state[RINGMOD_STATE_TOP-1 -: 1];
	reg d_ringmod_state = 0;

	localparam WF_BITS = 3;
	wire [WF_BITS-1:0] wf;
	localparam WF_SAW = 0;
	localparam WF_SAW_2BIT = 1;
	localparam WF_TRIANGLE = 2;
	localparam WF_TRIANGLE_2BIT = 3;
	localparam WF_SQUARE = 4;
	localparam WF_PULSE_5_3 = 5;
	localparam WF_PULSE_6_2 = 6;
	localparam WF_PULSE_7_1 = 7;

	localparam PHASE_SHL_BITS = 2;
	wire [PHASE_SHL_BITS-1:0] phase0_shl, phase1_shl;
	localparam PHASECOMB_BITS = 2;
	localparam PHASECOMB_PP = 0;
	localparam PHASECOMB_PM = 1;
	localparam PHASECOMB_P0 = 2;
	localparam PHASECOMB_0P = 3;
	wire [PHASECOMB_BITS-1:0] phase_comb;
	// not actual registers
	reg pass_phase0, pass_phase1, invert_phase1;
	always @(*) begin
		case(phase_comb)
			PHASECOMB_PP: begin pass_phase0 = 1; pass_phase1 = 1; invert_phase1 = 0; end
			PHASECOMB_PM: begin pass_phase0 = 1; pass_phase1 = 1; invert_phase1 = 1; end
			PHASECOMB_P0: begin pass_phase0 = 1; pass_phase1 = 0; invert_phase1 = 1'bX; end
			PHASECOMB_0P: begin pass_phase0 = 0; pass_phase1 = 1; invert_phase1 = 0; end
		endcase
	end


	localparam WFSIGNVOL_BITS = 3;
	wire [WFSIGNVOL_BITS-1:0] wfsignvol;
	wire wf_sign;
	wire [WFSIGNVOL_BITS-2:0] rshift_wfvol;
	assign {wf_sign, rshift_wfvol} = wfsignvol;
	wire wf_on = wfsignvol != '1;

	wire ringmod;

	localparam WF_PARAM_BITS = WF_BITS + 2*PHASE_SHL_BITS + PHASECOMB_BITS + WFSIGNVOL_BITS + 1;
	assign {ringmod, wfsignvol, phase_comb, phase1_shl, phase0_shl, wf} = wf_params;

	localparam PARAM_BIT_WF_PARAMS0 = 0;
	localparam PARAM_BIT_WF0 = PARAM_BIT_WF_PARAMS0;
	localparam PARAM_BIT_PHASE0_SHL = PARAM_BIT_WF0 + WF_BITS;
	localparam PARAM_BIT_PHASE1_SHL = PARAM_BIT_PHASE0_SHL + PHASE_SHL_BITS;
	localparam PARAM_BIT_PHASECOMB = PARAM_BIT_PHASE1_SHL + PHASE_SHL_BITS;
	localparam PARAM_BIT_WFSIGNVOL = PARAM_BIT_PHASECOMB + PHASECOMB_BITS;
	localparam PARAM_BIT_RINGMOD = PARAM_BIT_WFSIGNVOL + WFSIGNVOL_BITS;

	localparam PARAM_BIT_LFSR = NUM_WFS*WF_PARAM_BITS;
	localparam PARAM_BITS = PARAM_BIT_LFSR + 1;

	localparam PARAM_TOP = RINGMOD_STATE_TOP + PARAM_BITS;
	wire [PARAM_BITS-1:0] params = state[PARAM_TOP-1 -: PARAM_BITS];
	reg [PARAM_BITS-1:0] d_params = 0;

	//wire [WF_BITS-1:0] wfs[NUM_WFS];
	wire [WF_PARAM_BITS-1:0] wfs_params[NUM_WFS];
	generate
		for (i=0; i < NUM_WFS; i++) begin
			//assign wfs[i] = params[PARAM_BIT_WF0 + WF_BITS*(i + 1) - 1 -: WF_BITS];
			assign wfs_params[i] = params[PARAM_BIT_WF_PARAMS0 + WF_PARAM_BITS*(i + 1) - 1 -: WF_PARAM_BITS];
		end
	endgenerate

	localparam VPARAM_BIT_TOPOLOGY = 0;
	localparam VPARAM_BIT_BPF = VPARAM_BIT_TOPOLOGY + 2;
	localparam VPARAM_BIT_HARDSYNC = VPARAM_BIT_BPF + NUM_WFS;
	localparam VPARAM_BIT_RESET_PHASE = VPARAM_BIT_HARDSYNC + 1;
	localparam RESET_PHASE_BITS = 4;
	localparam VPARAM_BIT_VOL = VPARAM_BIT_RESET_PHASE + RESET_PHASE_BITS;
	localparam VOICE_VOL_BITS = 2;
	localparam VPARAM_BITS = VPARAM_BIT_VOL + VOICE_VOL_BITS;

	localparam VPARAM_TOP = PARAM_TOP + VPARAM_BITS;
	wire [VPARAM_BITS-1:0] vparams = state[VPARAM_TOP-1 -: VPARAM_BITS];
	reg [VPARAM_BITS-1:0] d_vparams = 0;

	wire [1:0] topology;
	wire [NUM_WFS-1:0] bpf_en;
	wire hardsync;
	wire [RESET_PHASE_BITS-1:0] hardsync_phase;
	wire [VOICE_VOL_BITS-1:0] voice_vol;
	assign {voice_vol, hardsync_phase, hardsync, bpf_en, topology} = vparams;



	localparam USED_STATE_BITS = VPARAM_TOP; // Must be highest top parameter

	// For testing
	wire [STATE_BITS-1:0] ostate = {
		d_params, d_ringmod_state, d_lfsr_extra, d_mods[2], d_mods[1], d_mods[0], d_float_period[1], d_float_period[0], d_v, d_y, d_running_counter,
		d_phase[1], d_phase[0], d_fir_offset_lsbs, d_delayed_p, d_delayed_s
	};

	reg [STATE_BITS-1:0] state;

	// Assign next values and write enables into state vectors
	// -------------------------------------------------------

	// Not actually registers
	reg [STATE_BITS-1:0] state_nx, state_we;
	always @(*) begin
		state_nx = 'X;
		state_we = '0;

		state_nx[DELAYED_S_TOP-1 -: 1] = delayed_s_next;
		state_we[DELAYED_S_TOP-1 -: 1] = delayed_s_we;

		state_nx[DELAYED_P_TOP-1 -: NUM_OSCS] = delayed_p_next;
		state_we[DELAYED_P_TOP-1 -: NUM_OSCS] = delayed_p_we; // per bit

		state_nx[FIR_OFFSET_TOP-1 -: SUBSAMP_BITS] = next_fir_offset[SUBSAMP_BITS-1:0];
		state_we[FIR_OFFSET_TOP-1 -: SUBSAMP_BITS] = !context_switch ? '1 : 0;

		state_nx[PHASE0_TOP-1 -: PHASE_BITS] = phase_next;
		state_we[PHASE0_TOP-1 -: PHASE_BITS] = phase_we[0] ? '1 : '0;
		state_nx[PHASE1_TOP-1 -: PHASE_BITS] = phase1_next;
		state_we[PHASE1_TOP-1 -: PHASE_BITS] = phase_we[1] ? '1 : '0;

		state_nx[LFSR_EXTRA_TOP-1 -: LFSR_EXTRA_BITS] = lfsr_extra_next;
		state_we[LFSR_EXTRA_TOP-1 -: LFSR_EXTRA_BITS] = lfsr_extra_we ? '1 : '0;

		state_nx[RINGMOD_STATE_TOP-1 -: 1] = ringmod_state_next;
		state_we[RINGMOD_STATE_TOP-1 -: 1] = ringmod_state_we;

		state_nx[RC_TOP-1 -: MOD_MANTISSA_BITS] = running_counter_next;
		state_we[RC_TOP-1 -: MOD_MANTISSA_BITS] = running_counter_we ? '1 : '0;

		state_nx[Y_TOP-1 -: SVF_STATE_BITS] = yv_next;
		state_we[Y_TOP-1 -: SVF_STATE_BITS] = y_we ? '1 : '0;
		state_nx[V_TOP-1 -: SVF_STATE_BITS] = yv_next;
		state_we[V_TOP-1 -: SVF_STATE_BITS] = v_we ? '1 : '0;

		state_nx[FP0_TOP-1 -: FP_BITS] = fp_next;
		state_we[FP0_TOP-1 -: FP_BITS] = fp_we[0] ? '1 : '0;
		state_nx[FP1_TOP-1 -: FP_BITS] = fp_next;
		state_we[FP1_TOP-1 -: FP_BITS] = fp_we[1] ? '1 : '0;

		state_nx[MOD0_TOP-1 -: MOD_BITS] = mod_next;
		state_we[MOD0_TOP-1 -: MOD_BITS] = mod_we[0] ? '1 : '0;
		state_nx[MOD1_TOP-1 -: MOD_BITS] = mod_next;
		state_we[MOD1_TOP-1 -: MOD_BITS] = mod_we[1] ? '1 : '0;
		state_nx[MOD2_TOP-1 -: MOD_BITS] = mod_next;
		state_we[MOD2_TOP-1 -: MOD_BITS] = mod_we[2] ? '1 : '0;
	end

/*
	// Update state vector
	// -------------------

	wire [STATE_BITS-1:0] state_scan_next = {scan_in, state[STATE_BITS-1:1]};
	generate
		for (i=0; i < STATE_BITS; i++) begin
			always @(posedge clk) begin
				if (scan || state_we[i]) state[i] <= scan ? state_scan_next[i] : state_nx[i];
			end
		end
	endgenerate
	assign scan_out = state[0];
*/
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
					if (scan_hit || state_we[i*WORD_SIZE + j]) state[i*WORD_SIZE + j] <= scan_hit ? next_state_scan[j] : state_nx[i*WORD_SIZE + j];
				end
			end
		end
	endgenerate

	wire [IO_BITS-1:0] scan_outs[STATE_WORDS];
	assign scan_out = scan_outs[read_index];

	// Non-state updates
	// -----------------

	always @(posedge clk) begin
		if (context_switch) begin
			fir_offset_msbs <= 0;
		end else begin
			fir_offset_msbs <= next_fir_offset[SAMP_BITS-1:SUBSAMP_BITS];
		end

		if (reset) begin
			oct_counter <= 0;
			sweep_oct_counter <= 0;
		end else begin
			if (oct_counter_we) oct_counter <= next_oct_counter;
			if (inc_sweep_oct_counter) sweep_oct_counter <= next_sweep_oct_counter;
		end

		if (wave_we) wave_reg <= wave;
	end

	// Shift adder
	// ===========
	wire acc_we = fir_enable && (term_index != 0);

//	wire [`TARGET_BITS-1:0] target_sel = acc_we ? `TARGET_ACC : `TARGET_NONE;
	wire [`A_SEL_BITS-1:0] a_sel = svf_enable ? a_sel_svf : (restart_acc ? `A_SEL_ZERO : `A_SEL_ACC);
//	wire [`B_SEL_BITS-1:0] b_sel = svf_enable ? b_sel_svf : `B_SEL_WAVE;
	wire [`B_SEL_BITS-1:0] b_sel = svf_enable ? b_sel_svf : `B_SEL_Y;
	wire flip_sign = svf_enable ? b_sign_svf ^ (svf_step == 1 && (wf_sign ^ ringmod_state)) : flip_sign_fir;

	wire [RSHIFT_BITS-1:0] rshift_base = svf_enable ? rshift_base_svf : rshift_reg0;
	//wire [RSHIFT_BITS-1:0] rshift_offs = svf_enable ? rshift_offs_svf : (delayed_s ? SUBSAMP_BITS : 0);
	wire [RSHIFT_BITS-1:0] rshift_offs = (svf_enable ? rshift_offs_svf : rshift_offs_fir) + (delayed_s ? SUBSAMP_BITS : 0);

	// Add, clamp
	wire [RSHIFT_BITS+1-1:0] rshift_ext = rshift_base + rshift_offs;
	//wire [RSHIFT_BITS-1:0] rshift = rshift_ext[RSHIFT_BITS] ? '1 : rshift_ext[RSHIFT_BITS-1:0];
	wire [RSHIFT_BITS-1:0] rshift = rshift_ext[RSHIFT_BITS-1:0];
	wire zero_shifter_out = rshift_ext[RSHIFT_BITS];

	// Pipeline registers
	reg [`A_SEL_BITS-1:0] a_sel_reg;
	reg [`B_SEL_BITS-1:0] b_sel_reg;
	reg flip_sign_reg;
	reg [RSHIFT_BITS-1:0] rshift_reg;
	reg zero_shifter_out_reg;

	reg scan_accs_reg;
	reg [`TARGET_BITS-1:0] target_reg;
	reg restart_acc_reg;

	//wire svf_actual_we = svf_we;
	//wire svf_actual_we = svf_we && !(svf_step == 1 && wf_index != 0); // Only add input at wf_index == 0 for now. TODO: do for all
	//wire svf_actual_we = svf_we && !(svf_step == 1 && (wf_index[1] != 0 || !wf_on)); // Only add input at wf_index == 0 or 1 for now. TODO: do for all
	wire svf_actual_we = svf_we && !(svf_step == 1 && !wf_on);
	wire [`TARGET_BITS-1:0] target = reset ? `TARGET_NONE : (acc_we ? `TARGET_ACC : (svf_actual_we ? (svf_target_v ? `TARGET_V : `TARGET_Y) : `TARGET_NONE));

	// Update pipeline registers
	always @(posedge clk) begin
		a_sel_reg <= a_sel;
		b_sel_reg <= b_sel;
		flip_sign_reg <= flip_sign;
		rshift_reg <= rshift;
		zero_shifter_out_reg <= zero_shifter_out;
		scan_accs_reg <= scan_accs;
		target_reg <= target;
		restart_acc_reg <= restart_acc;
	end


	// Not registers
	reg signed [SHIFTADD_BITS-1:0] src_a, src_b;
	wire a_sign = src_a[SHIFTADD_BITS-1];

	always @(*) begin
		src_a = 'X;
		src_b = 'X;
		case (a_sel_reg)
			`A_SEL_ZERO: src_a = 0;
			`A_SEL_ACC:  src_a = acc;
			`A_SEL_Y:    src_a = y;
			`A_SEL_V:    src_a = v;
		endcase
		case (b_sel_reg)
			`B_SEL_WAVE: src_b = {wave_reg, {(SHIFTADD_BITS - WAVE_BITS){1'b0}}};
			`B_SEL_Y:    src_b = y;
			`B_SEL_V:    src_b = v;
		endcase
	end


	wire signed [SHIFTADD_BITS+1-1:0] shifter_in = {src_b ^ (flip_sign_reg ? '1 : '0), flip_sign_reg};
	// CONSIDER: Better way to zero the shifter output?
	wire signed [SHIFTADD_BITS+1-1:0] shifter_out = zero_shifter_out_reg ? 0 : (shifter_in >>> rshift_reg);
	wire shifter_out_sign = shifter_out[SHIFTADD_BITS+1-1];

	wire signed [SHIFTADD_BITS:0] shift_sum00 = ($signed({src_a, 1'b1}) + shifter_out);
	wire signed [SHIFTADD_BITS-1:0] shift_sum0 = shift_sum00[SHIFTADD_BITS:1];
	wire shift_sum0_sign = shift_sum0[SHIFTADD_BITS-1];

	// Saturate shift adder output
	// ---------------------------
	wire shift_max = ~a_sign & ~shifter_out_sign &  shift_sum0_sign;
	wire shift_min =  a_sign &  shifter_out_sign & ~shift_sum0_sign;
	wire shift_sat = shift_max | shift_min;
	wire [SHIFTADD_BITS-1:0] shift_sat_value = {~shift_max, {(SHIFTADD_BITS-1){shift_max}}};
	wire [SHIFTADD_BITS-1:0] shift_sum = shift_sat ? shift_sat_value : shift_sum0[SHIFTADD_BITS-1:0];


	// State variable filter
	// =====================
	reg [MOD_MANTISSA_BITS-1:0] d_running_counter = 0;
	reg [MOD_BITS-1:0] d_mods[NUM_MODS];

	reg [SVF_STATE_BITS-1:0] d_y = 0, d_v = 0;

	wire [`A_SEL_BITS-1:0] a_sel_svf;
	wire [`B_SEL_BITS-1:0] b_sel_svf;
	wire [`MOD_SEL_BITS-1:0] mod_sel;
	wire b_sign_svf, svf_we, svf_target_v;
	SVF_controller svf_controller(
		.step(svf_step), .topology(topology), .wf_index(wf_index), .bpf_en(bpf_en[wf_index]), .en(svf_enable),
		.a_sel(a_sel_svf), .b_sel(b_sel_svf), .mod_sel(mod_sel),
		.b_sign(b_sign_svf), .we(svf_we), .target_v(svf_target_v)
	);

	wire [MOD_BITS-1:0] curr_mod = mods[mod_sel];
	wire [OCT_BITS-1:0] curr_mod_oct;
	wire [MOD_MANTISSA_BITS-1:0] curr_mod_mantissa;
	assign {curr_mod_oct, curr_mod_mantissa} = curr_mod;

	wire [MOD_MANTISSA_BITS-1:0] rev_rc;
	generate
		for (i = 0; i < MOD_MANTISSA_BITS; i++) assign rev_rc[i] = running_counter[MOD_MANTISSA_BITS - 1 - i];
	endgenerate

	wire [RSHIFT_BITS-1:0] rshift_base_svf = curr_mod_oct;
	wire [RSHIFT_BITS-1:0] rshift_offs_svf = {{(RSHIFT_BITS-1){1'b0}}, (curr_mod_mantissa > rev_rc)} + (svf_step == 1 ? rshift_wfvol : 0);


	// Waveform generator
	// ==================
	//wire [WF_BITS-1:0] wf = wfs[wf_index];
	wire [WF_PARAM_BITS-1:0] wf_params = wfs_params[wf_index];

	wire [PHASE_BITS-1:0] wphase = phase_sum2;
	wire [2:0] wphase3 = wphase[PHASE_BITS-1 -: 3];
	// Not an actual register
	reg signed [WAVE_BITS-1:0] wave;
	always @(*) begin
		case (wf)
			WF_SAW, WF_SAW_2BIT: wave =  {~wphase[PHASE_BITS-1], wphase[PHASE_BITS-2:0]};
			WF_TRIANGLE, WF_TRIANGLE_2BIT: wave = {~wphase[PHASE_BITS-2], wphase[PHASE_BITS-3:0], 1'b0} ^ (wphase[PHASE_BITS-1] ? -1: 0);
			WF_SQUARE: wave = (1 << (PHASE_BITS - 1)) ^ (wphase[PHASE_BITS-1] ? -1: 0);
			WF_PULSE_5_3: wave = {wphase3 < 5, 3'd5, {(WAVE_BITS-4){1'b0}}};
			WF_PULSE_6_2: wave = {wphase3 < 6, 3'd6, {(WAVE_BITS-4){1'b0}}};
			WF_PULSE_7_1: wave = {wphase3 < 7, 3'd7, {(WAVE_BITS-4){1'b0}}};
		endcase
		if (wf == WF_SAW_2BIT || wf == WF_TRIANGLE_2BIT) begin
			wave = {wave[WAVE_BITS-1 -: 2], 1'b1, {(WAVE_BITS-3){1'b0}}};
		end
	end

	// FIR filter
	// ==========

	reg [ACC_BITS-1:0] accs[NUM_ACCS];

	wire scan_accs = (fir_enable && (term_index == 0) && !(step_sample && tap == 0)) || ext_scan_accs;

	generate
		for (i=0; i < NUM_ACCS-1; i++) begin
			always @(posedge clk) begin
				if (reset) begin
					accs[i+1] <= 0; // TODO: not needed
				end else begin
					if (scan_accs_reg) accs[i+1] <= accs[i];
				end
			end
		end
	endgenerate

	/*
	reg [7:0] dbg_scan_accs_counter;
	always @(posedge clk) begin
		if (reset) dbg_scan_accs_counter <= 0;
		else dbg_scan_accs_counter <= dbg_scan_accs_counter + scan_accs_reg;
	end
	*/

	localparam WAVE_BITS = PHASE_BITS;
	localparam RSHIFT_BITS = 4; //$clog2(WAVE_BITS); // TODO: enough?
	localparam LOG2_NUM_OUT_TAPS = $clog2(FIR_OUT_TAPS);
	localparam TERM_INDEX_BITS = $clog2(MAX_TERMS_PER_COEFF);


	reg [LOG2_NUM_OUT_TAPS-1:0] tap;
	reg [TERM_INDEX_BITS-1:0] term_index;
	wire [TERM_INDEX_BITS-1:0] last_term_index;

	wire coeff_done = fir_enable && (term_index == last_term_index);
	wire taps_done = coeff_done && (tap == FIR_OUT_TAPS - 1);


	wire [RSHIFT_BITS-1:0] rshift0;
	reg [RSHIFT_BITS-1:0] rshift_reg0;
	wire [RSHIFT_BITS-1:0] rshift_offs_fir = {{(RSHIFT_BITS - VOICE_VOL_BITS){1'b0}}, voice_vol};

	reg [SUPERSAMP_BITS-1:0] fir_offset_msbs;
	reg [SUBSAMP_BITS-1:0] d_fir_offset_lsbs = 0;
	wire [SAMP_BITS+1-1:0] next_fir_offset = fir_offset + (main_osc_enable ? (delayed_s ? 1 : 2**SUBSAMP_BITS) : 0);
	assign sample_done = next_fir_offset[SAMP_BITS];

	wire [LOG2_NUM_OUT_TAPS+SAMP_BITS-1:0] coeff_index = {tap, fir_offset};
	wire [LOG2_NUM_OUT_TAPS+1-1:0] top_coeff_index = coeff_index[LOG2_NUM_OUT_TAPS+SAMP_BITS-1 : SAMP_BITS-1];
	wire fci_high = top_coeff_index >= FIR_OUT_TAPS;
	wire [LOG2_NUM_OUT_TAPS-1:0] top_coeff_index_m = fci_high ? (FIR_OUT_TAPS*2 - 1) - top_coeff_index : top_coeff_index;
	wire [LOG2_NUM_OUT_TAPS+SAMP_BITS-1-1:0] coeff_index_m = {top_coeff_index_m, coeff_index[SAMP_BITS-1-1:0] ^ {(SAMP_BITS-1){fci_high}}};

	reg flip_sign_fir;
	wire flip_sign0;

	fir_table48 fir_table(
		.i_coeff(coeff_index_m), .i_term(term_index),
		.last_term_index(last_term_index), .term_sign(flip_sign0), .term_exp(rshift0)
	);

	wire restart_acc = new_sample && (tap == 0) && (term_index == 1);

	wire signed [ACC_BITS-1:0] acc = accs[0];

	always @(posedge clk) begin
		//Output old acc externally instead
		//if (restart_acc_reg) out_reg <= acc; // old acc is ignored; output it

		if (reset) begin
			accs[0] <= 0; // TODO: not needed
		end else begin
			// term_index = 0 ==> haven't loaded new term yet
			if (scan_accs_reg) accs[0] <= accs[NUM_ACCS-1];
			//else if (acc_we) accs[0] <= shift_sum;
			else if (target_reg == `TARGET_ACC) accs[0] <= shift_sum;
		end

		if (reset || taps_done) begin
			tap <= 0;
		end else begin
			tap <= tap + coeff_done;
		end

		if (reset || coeff_done) begin
			term_index <= 0;
		end else begin
			term_index <= term_index + {{(TERM_INDEX_BITS-1){1'b0}}, fir_enable};
		end

		// register FIR table outputs
		flip_sign_fir <= flip_sign0;
		rshift_reg0 <= rshift0;
	end

	// Sweeps
	// ======
	localparam FP_MOD_DELTA_BITS = PHASE_BITS - MOD_MANTISSA_BITS;

	// NB: Hardcoded for 2 oscillators and 3 mods
	wire [FP_BITS-1:0] sweep_fp_fp = sweep_index[0] ? float_period[1] : float_period[0];
	wire [MOD_BITS-1:0] sweep_mod = sweep_index[1] ? (sweep_index[0] ? mods[1] : mods[0]) : mods[2];
	wire sweep_source_is_mod = sweep_index[2:1] != 0;
	//wire [FP_BITS-1:0] sweep_fp = sweep_source_is_mod ? sweep_mod << FP_MOD_DELTA_BITS: sweep_fp_fp;
	wire [FP_BITS-1:0] sweep_fp = sweep_source_is_mod ? {sweep_mod[FP_BITS-FP_MOD_DELTA_BITS-1:0], {FP_MOD_DELTA_BITS{1'b0}}}: sweep_fp_fp;
	wire [SWEEP_MANTISSA_BITS+1-1:0] sweep_fp_lsbs = sweep_source_is_mod ? sweep_mod[SWEEP_MANTISSA_BITS:0] : sweep_fp_fp[SWEEP_MANTISSA_BITS:0];

	// Unpack sweep data
	wire sweep_sign;
	wire [OCT_BITS-1:0] sweep_oct;
	wire [SWEEP_MANTISSA_BITS-1:0] sweep_mantissa;
	// TODO: Use msbs of rx_buffer to avoid flipflops for the lsbs
	assign {sweep_sign, sweep_oct, sweep_mantissa} = rx_buffer[1+OCT_BITS+SWEEP_MANTISSA_BITS-1:0];

	wire sweep_nreplace;
	wire [FP_BITS-1:0] sweep_replace_data;
	assign {sweep_nreplace, sweep_replace_data} = rx_buffer[FP_BITS+1-1:0];
	wire sweep_replace = !sweep_nreplace;

	wire sweep_step = sweep_oct_enables[sweep_oct];
	// TODO: Saturate exactly at max/min even if taking bigger steps?
	wire apply_sweep = sweep_data_valid && ((sweep_step && !sweep_sat) || sweep_replace);

	wire [SWEEP_MANTISSA_BITS-1:0] rev_sweep_fp;
	// Don't put sweep_fp_lsbs into rev_sweep_fp; it is used as delayed bit
	generate
		for (i = 0; i < SWEEP_MANTISSA_BITS; i++) assign rev_sweep_fp[i] = sweep_fp_lsbs[SWEEP_MANTISSA_BITS+1-1 - i];
	endgenerate

	wire sweep_big_step = !sweep_fp_lsbs[0] && !(sweep_mantissa > rev_sweep_fp);

	wire [FP_BITS-1:0] sweep_delta0 = (sweep_sign ? -1 : 1) << sweep_big_step;
	wire [FP_BITS-1:0] sweep_delta = sweep_source_is_mod ? sweep_delta0 << FP_MOD_DELTA_BITS : sweep_delta0;
	wire [FP_BITS+1-1:0] sweep_sum = sweep_fp + sweep_delta;
	wire sweep_sat = (sweep_sum[FP_BITS] != sweep_sign);

	wire [FP_BITS-1:0] sweep_out = sweep_replace ? sweep_replace_data : sweep_sum[FP_BITS-1:0];

	assign fp_next  = sweep_out[FP_BITS-1:0];
	assign mod_next = sweep_out[FP_BITS-1 -: MOD_BITS];

	assign fp_we[0] = apply_sweep && sweep_index == 0;
	assign fp_we[1] = apply_sweep && sweep_index == 1;

	assign mod_we[0] = apply_sweep && sweep_index == 2;
	assign mod_we[1] = apply_sweep && sweep_index == 3;
	assign mod_we[2] = apply_sweep && sweep_index == 4;

	// Output assignments
	// ==================
	assign out_valid = restart_acc_reg;
	assign out = acc[ACC_BITS-1 -: WORD_SIZE]; // Assumes ACC_BITS >= WORD_SIZE

	assign fir_done = taps_done;
	assign fir_prepare = fir_enable && (term_index == 0);
	assign tap_pos = tap;
endmodule : subsamp_voice

module subsamp_voice_controller #(
		parameter LOG2_NUM_VOICES = 2, LOG2_NUM_SAMPLES_PER_VOICE = 2, NUM_SVF_CYCLES = 4,
		ROT_BACK = 3, ROT_SWITCH_STEP = 3,
		NUM_OSCS = 2, FIR_OUT_TAPS = 3,
		IO_BITS=2, PAYLOAD_CYCLES=8, STATE_WORDS=`STATE_WORDS,
		NUM_SWEEPS=5,
		SAMPLE_CREDIT_BITS = 2, SBIO_CREDIT_BITS = 3
	) (
		input wire clk, reset,

		input wire scan_ready,

		output wire new_sample, step_sample, ext_scan_accs, rewind_out_sample, inc_sweep_oct_counter,
		output wire [NUM_OSCS-1:0] osc_enable, 
		output wire fir_enable,
		input wire fir_done, sample_done,
		input wire fir_prepare, // goes high when fir_enable and FIR filter is not using the shift adder
		input wire [$clog2(FIR_OUT_TAPS)-1:0] tap_pos,

		output reg svf_enable,
		output reg [`SVF_STEP_BITS-1:0] svf_step,
		output reg [`LOG2_NUM_WFS-1:0] wf_index,

		output wire context_switch,
		output wire [$clog2(STATE_WORDS + 1)-1:0] read_index, write_index,
		output wire [IO_BITS-1:0] scan_in,
		input wire [IO_BITS-1:0] scan_out,

		output reg [PAYLOAD_CYCLES*IO_BITS-1:0] rx_buffer,
		output wire sweep_data_valid,
		output wire [$clog2(NUM_SWEEPS)-1:0] sweep_index,

		input wire out_valid, // new sample when high; out must be sampled on that cycle
		input wire signed [PAYLOAD_CYCLES*IO_BITS-1:0] out,

		output wire [IO_BITS-1:0] tx_pins,
		input wire [IO_BITS-1:0] rx_pins,

		output wire [7:0] ppu_ctrl,

		input wire ext_tx_request,
		//input wire [IO_BITS-1:0] ext_tx_data,
		//output wire ext_tx_scan, // ask for next data bits
		output wire ext_tx_ack
	);

	localparam FIRST_FIR_COUNT = 0;
	localparam FIRST_SVF_COUNT = FIRST_FIR_COUNT + 1;
	localparam LAST_SVF_COUNT = FIRST_SVF_COUNT + NUM_SVF_CYCLES - 1;
//	localparam FIRST_SWITCH_COUNT = LAST_SVF_COUNT + 2; // Allow an extra cycle for y or v to be written before starting to scan
	localparam FIRST_SWITCH_COUNT = LAST_SVF_COUNT + 1;

	localparam LOG2_NUM_SWITCHES_PER_SAMPLE = LOG2_NUM_VOICES - LOG2_NUM_SAMPLES_PER_VOICE;
	localparam NUM_SWITCHES_PER_SAMPLE = 2**LOG2_NUM_SWITCHES_PER_SAMPLE;

	localparam NUM_CONTEXT_CYCLES = ROT_SWITCH_STEP + 2; // Allow one extra cycle before to maybe rotate accs, one last to not.

	localparam COUNTER_CYCLES = FIRST_SWITCH_COUNT + NUM_CONTEXT_CYCLES;
	localparam COUNTER_BITS = $clog2(COUNTER_CYCLES);


	localparam WORD_SIZE = PAYLOAD_CYCLES * IO_BITS;
	//localparam STATE_BITS = WORD_SIZE * STATE_WORDS;

	localparam INDEX_BITS = $clog2(STATE_WORDS + 1); // One extra so that '1 can mean idle

	localparam SBIO_COUNTER_BITS = $clog2(PAYLOAD_CYCLES) + 1;


	reg step_sample_reg;
	reg [LOG2_NUM_VOICES-1:0] curr_voice;
	reg [LOG2_NUM_SAMPLES_PER_VOICE-1:0] sample_counter;
	reg [COUNTER_BITS-1:0] counter;

	wire forward_voice = (curr_voice & (NUM_SWITCHES_PER_SAMPLE - 1)) == 0;
	wire forward_voice_next = (curr_voice & (NUM_SWITCHES_PER_SAMPLE - 1)) == (NUM_SWITCHES_PER_SAMPLE - 1);

	wire step = !((fir_enable && !fir_done) || (want_scan && !scan_actually_ready) || (counter == COUNTER_CYCLES - 1 && !scan_done));

	// There should be no risk that we reach scan_done before counter reaches the last cycle,
	// otherwise need to remember scan_done until it does
	wire inc_voice = step && (counter == COUNTER_CYCLES - 1) && scan_done;
	wire inc_sample = osc_enable[0] && sample_done;

	wire [LOG2_NUM_SAMPLES_PER_VOICE+1-1:0] next_sample_counter = sample_counter + {{(LOG2_NUM_SAMPLES_PER_VOICE){1'b0}}, inc_sample};
	wire restart_without_switch = osc_enable[0] && !next_sample_counter[LOG2_NUM_SAMPLES_PER_VOICE];

	wire restart_counter = inc_voice || restart_without_switch;

	wire [LOG2_NUM_VOICES+1-1:0] next_voice = curr_voice + {{(LOG2_NUM_VOICES){1'b0}}, inc_voice};

	always @(posedge clk) begin
		if (reset) begin
			counter <= FIRST_SWITCH_COUNT; // 0
			sample_counter <= 0;
			curr_voice <= 2**LOG2_NUM_VOICES - 1; // 0;
			step_sample_reg <= 1;
		end else if (step) begin
			if (restart_counter) begin
				counter <= 0; // CONSIDER: merge this reset with the reset case
				step_sample_reg <= (sample_done || want_scan);
			end else begin
				counter <= counter + 1;
			end
			curr_voice <= next_voice[LOG2_NUM_VOICES-1:0];
			//curr_voice <= next_voice & (2**LOG2_NUM_VOICES - 1);
			//sample_counter <= next_sample_counter & (2**LOG2_NUM_SAMPLES_PER_VOICE - 1);
			sample_counter <= next_sample_counter[LOG2_NUM_SAMPLES_PER_VOICE-1:0];
		end
	end
	// Should activate once when curr_voice rolls over to zero.
	assign inc_sweep_oct_counter = next_voice[LOG2_NUM_VOICES] && step;

	assign fir_enable = (counter == FIRST_FIR_COUNT);

	// CONSIDER: more efficient way to compute these together?
	assign osc_enable[0] = (counter == LAST_SVF_COUNT);
	assign osc_enable[1] = (counter == LAST_SVF_COUNT - 1);

	wire want_scan = counter >= FIRST_SWITCH_COUNT;
	assign context_switch = want_scan && scan_actually_ready;
	assign start_scan = (counter == FIRST_SWITCH_COUNT) && step;

	assign new_sample = step_sample_reg && forward_voice && (sample_counter == (2**LOG2_NUM_SAMPLES_PER_VOICE - 1));
	assign step_sample = step_sample_reg;

	wire ext_scan_accs_rot_back = !fir_enable && (counter < 1 + ROT_BACK);
	wire ext_scan_accs_rot_switch = context_switch && (counter < FIRST_SWITCH_COUNT + ROT_SWITCH_STEP + 1) && (counter != FIRST_SWITCH_COUNT || !forward_voice_next);
	assign ext_scan_accs = ext_scan_accs_rot_back || ext_scan_accs_rot_switch;
	assign rewind_out_sample = ext_scan_accs_rot_switch;

	// Distribute SVF updates into the cycles that don't use the shift adder for something else (or do context switching).
	// Assumes 3 taps, 4 waveforms, NUM_SVF_CYCLES = 4
	always @(*) begin
		svf_enable = 0;
		svf_step = 'X;
		wf_index = 'X;

		if (fir_prepare) begin
			svf_enable = 1;
			case (tap_pos)
				0: svf_step = 3;
				1: svf_step = 0;
				2: begin
					//svf_step = 1;
					//wf_index = 0;
					svf_enable = 0;
				end
			endcase
		end else if (!fir_enable && counter <= LAST_SVF_COUNT) begin
			svf_enable = 1;
			if (counter == FIRST_SVF_COUNT) begin
				svf_step = 2;
			end else begin
				svf_step = 1;
				//wf_index = counter - FIRST_SVF_COUNT;
				wf_index = counter - (FIRST_SVF_COUNT + 1);
			end
		end
	end

	// Sample output
	// =============
	reg out_reg_valid;
	reg [WORD_SIZE-1:0] out_reg;
	wire scan_out_reg;

	always @(posedge clk) begin
		if (reset) begin
			out_reg_valid <= 0;
		end else begin
			if (out_valid) out_reg_valid <= 1;
			else if (tx_done_out) out_reg_valid <= 0;
		end

		if (out_valid) begin
			out_reg <= out;
		end else begin
			if (scan_out_reg) out_reg <= out_reg >> IO_BITS;
		end
	end

	// Sweep reading
	// =============
	localparam SWEEP_INDEX_BITS = $clog2(NUM_SWEEPS+1);

	reg [SWEEP_INDEX_BITS-1:0] sweep_addr_index;
	wire sending_sweep_addrs = (sweep_addr_index != NUM_SWEEPS);

	wire [WORD_SIZE-1:0] tx_read_addr = {{(WORD_SIZE-LOG2_NUM_VOICES-SWEEP_INDEX_BITS){1'b0}}, {curr_voice, sweep_addr_index}};

	reg [SWEEP_INDEX_BITS-1:0] sweep_data_index;
	wire awaiting_sweep_data = (sweep_data_index != NUM_SWEEPS);

	// Wait for the sweeps to be received and applied,
	// and until we have sample credits -- it has to block somewhere...
	wire scan_actually_ready = scan_ready && !awaiting_sweep_data && have_sample_credits;

	always @(posedge clk) begin
		if (reset) begin
			sweep_addr_index <= NUM_SWEEPS;
			sweep_data_index <= NUM_SWEEPS;
		end else begin
			if (inc_voice) begin
				sweep_addr_index <= 0;
				sweep_data_index <= 0;
			end else begin
				sweep_addr_index <= sweep_addr_index + {{(SWEEP_INDEX_BITS-1){1'b0}}, tx_done_addr};
				sweep_data_index <= sweep_data_index + {{(SWEEP_INDEX_BITS-1){1'b0}}, sweep_data_valid};
			end
		end
	end

	assign sweep_index = sweep_data_index[$clog2(NUM_SWEEPS)-1:0];

	// Registers
	// =========
	wire reg_we = regwrite_data_valid;
	wire [`REG_ADDR_BITS-1:0] reg_waddr;
	wire [7:0] reg_wdata;
	assign {reg_waddr, reg_wdata} = rx_buffer[`REG_ADDR_BITS+8-1:0];

	reg [SAMPLE_CREDIT_BITS-1:0] sample_credits;
	wire have_sample_credits = (sample_credits != 0);

	reg [SBIO_CREDIT_BITS-1:0] sbio_credits;
	reg [7:0] ppu_ctrl_reg;
	assign ppu_ctrl = ppu_ctrl_reg;

	always @(posedge clk) begin
		if (reset) begin
			sample_credits <= 1; // 0; // To allow tests to start up. TODO: Should it start at zero?
			sbio_credits <= 1;
			ppu_ctrl_reg <= `PPU_CTRL_INITIAL;
		end else begin
			if (reg_we && (reg_waddr == `REG_ADDR_SAMPLE_CREDITS)) sample_credits <= reg_wdata[SAMPLE_CREDIT_BITS-1:0];
			else sample_credits <= sample_credits - out_valid;

			if (reg_we && (reg_waddr == `REG_ADDR_SBIO_CREDITS)) sbio_credits <= reg_wdata[SBIO_CREDIT_BITS-1:0];
			if (reg_we && (reg_waddr == `REG_ADDR_PPU_CTRL)) ppu_ctrl_reg <= reg_wdata;
		end
	end

	// Context switching
	// =================
	wire start_scan;

	wire reading, writing;

	reg scanning_out;

	reg [INDEX_BITS-1:0] read_index_reg, write_index_reg;

	wire [INDEX_BITS-1:0] next_read_index_reg  = read_index_reg  + {{(INDEX_BITS-1){1'b0}}, tx_done_reading};
	wire [INDEX_BITS-1:0] next_write_index_reg = write_index_reg + {{(INDEX_BITS-1){1'b0}}, rx_done_writing};

	wire scan_out_done = tx_done_reading && (read_index_reg  == STATE_WORDS - 1);
	wire scan_done     = rx_done_writing && (write_index_reg == STATE_WORDS - 1);

	assign read_index  = reading ? read_index_reg  : '1;
	assign write_index = writing ? write_index_reg : '1;

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

	// TX
	// --
	wire tx_active; //, tx_started;
	wire [SBIO_COUNTER_BITS-1:0] tx_counter;
	wire tx_done;
	sbio_monitor #(
		.IO_BITS(IO_BITS), .SENS_BITS(1), .COUNTER_BITS(SBIO_COUNTER_BITS),
		//.INACTIVE_COUNTER_VALUE(2**SBIO_COUNTER_BITS-2)
		.INACTIVE_COUNTER_VALUE({{(SBIO_COUNTER_BITS-1){1'b1}}, 1'b0}) // = 2**SBIO_COUNTER_BITS-2
	) sbio_tx (
		.clk(clk), .reset(reset),
		.pins(tx_pins),
		//.start(tx_started), // Not needed, we should know when we start it
		.active(tx_active), .done(tx_done), .counter(tx_counter)
	);

	// Who is controlling the current transmission? Only valid if there is one ongoing.
	reg [`TX_SOURCE_BITS-1:0] tx_source;
	reg [SBIO_CREDIT_BITS-1:0] tx_outstanding;
	wire have_sbio_credits = tx_outstanding < sbio_credits;

	// Prioritize between traffic sources
	wire tx_start_scan = scanning_out;
	wire tx_start_out = out_reg_valid;
	wire tx_start_read_sweep = sending_sweep_addrs;

	wire tx_start = !tx_active && (
		((tx_start_scan || tx_start_read_sweep) && have_sbio_credits) ||
		(tx_start_out || ext_tx_request));
	wire [`TX_SOURCE_BITS-1:0] next_tx_source = ext_tx_request ? `TX_SOURCE_EXT_OUT : (
		tx_start_out ? `TX_SOURCE_OUT : (tx_start_read_sweep ? `TX_SOURCE_READ : `TX_SOURCE_SCAN));
	always @(posedge clk) if (tx_start) tx_source <= next_tx_source;

	wire sbio_credit_out = tx_start && (next_tx_source == `TX_SOURCE_SCAN || next_tx_source == `TX_SOURCE_READ);

	wire tx_data = (tx_counter[SBIO_COUNTER_BITS-1] == 0); // High if transmitting data. Low during start bits and header.

	// TODO: Limit number of outstanding (unanswered) transactions
	wire tx_state = (tx_source == `TX_SOURCE_SCAN) && tx_data; // High if transmitting state. Low during start bits and header.
	assign reading = tx_state;
	assign scan_out_reg = (tx_source == `TX_SOURCE_OUT) && tx_data;

	wire [IO_BITS-1:0] tx_read_addr_bits = tx_read_addr[tx_counter*IO_BITS+IO_BITS-1 -: IO_BITS];

	// Choose tx data source
	// TODO: Use external bits if tx_source == `TX_SOURCE_EXT_OUT
	assign tx_pins = tx_start ? 1 : (!tx_active ? 0 : (tx_data ? (tx_source == `TX_SOURCE_READ ? tx_read_addr_bits : (tx_source == `TX_SOURCE_OUT ? out_reg[IO_BITS-1:0] : scan_out)) : tx_source));

	assign tx_done = (tx_counter == PAYLOAD_CYCLES - 1);
	wire tx_done_reading = tx_done && (tx_source == `TX_SOURCE_SCAN);
	wire tx_done_out     = tx_done && (tx_source == `TX_SOURCE_OUT);
	wire tx_done_addr    = tx_done && (tx_source == `TX_SOURCE_READ);
	assign ext_tx_ack    = tx_done && (tx_source == `TX_SOURCE_EXT_OUT);

	wire signed [1:0] sbio_credot_diff0 = {1'b0, sbio_credit_out} - {1'b0, sbio_credit_back};
	wire signed [SBIO_CREDIT_BITS-1:0] sbio_credot_diff = {{(SBIO_CREDIT_BITS-2){sbio_credot_diff0[1]}}, sbio_credot_diff0};
	always @(posedge clk) begin
		if (reset) begin
			tx_outstanding <= 0;
		end else begin
			tx_outstanding <= tx_outstanding + sbio_credot_diff;
		end
	end

	// RX
	// --
	wire rx_started, rx_active;
	wire [SBIO_COUNTER_BITS-1:0] rx_counter;
	wire rx_done;
	sbio_monitor #(
		.IO_BITS(IO_BITS), .SENS_BITS(2), .COUNTER_BITS(SBIO_COUNTER_BITS),
		//.INACTIVE_COUNTER_VALUE(2**SBIO_COUNTER_BITS-1)
		.INACTIVE_COUNTER_VALUE({SBIO_COUNTER_BITS{1'b1}}) // = 2**SBIO_COUNTER_BITS-1
	) sbio_rx (
		.clk(clk), .reset(reset),
		.pins(rx_pins),
		.start(rx_started), .active(rx_active), .done(rx_done), .counter(rx_counter)
	);

	reg rx_buffer_valid;
	//reg [WORD_SIZE-1:0] rx_buffer;

	reg [IO_BITS-1:0] rx_sbs; // Start bits from last start
	always @(posedge clk) begin
		if (rx_started) rx_sbs <= rx_pins;
	end

	wire sbio_credit_back = rx_started && (rx_pins == `RX_SB_SCAN || rx_pins == `RX_SB_READ);

	// Require start bits = 2'd1 to recognize context switch message
	wire rx_data = (rx_counter[SBIO_COUNTER_BITS-1] == 0);
	wire rx_mode_state = (rx_sbs == `RX_SB_SCAN);
	wire rx_state = rx_mode_state && rx_data; // High if receiving state. Low during start bits and header.
	assign writing = rx_state;
	assign scan_in = rx_pins;
	// Assumes that all messages have length described by PAYLOAD_CYCLES
	assign rx_done = (rx_counter == PAYLOAD_CYCLES - 1);
	wire rx_done_writing = rx_done && rx_mode_state;
	wire rx_done_read    = rx_done && (rx_sbs == `RX_SB_READ);
	assign sweep_data_valid = rx_buffer_valid && (rx_sbs == `RX_SB_READ);
	wire regwrite_data_valid = rx_buffer_valid && (rx_sbs == `RX_SB_WRITE);

	always @(posedge clk) begin
		if (reset) begin
			rx_buffer_valid <= 0;
		end else begin
			rx_buffer_valid <= rx_done; // Marked as valid for any kind of incoming data
		end

		if (rx_data) rx_buffer <= {rx_pins, rx_buffer[WORD_SIZE-1:IO_BITS]};
	end
endmodule : subsamp_voice_controller

module anemonesynth_top #(
		parameter NUM_OSCS = 2, FIR_OUT_TAPS = 3,
		IO_BITS = 2, PAYLOAD_CYCLES = 8, STATE_WORDS = `STATE_WORDS,
		NUM_SWEEPS = 5,
		//LOG2_NUM_VOICES = 1, LOG2_NUM_SAMPLES_PER_VOICE = 1, NUM_ACCS = 4, ROT_BACK = 1, ROT_SWITCH_STEP = 1, ACC_BITS = 20 //14
		LOG2_NUM_VOICES = 2, LOG2_NUM_SAMPLES_PER_VOICE = 2, NUM_ACCS = 6, ROT_BACK = 3, ROT_SWITCH_STEP = 3, ACC_BITS = 20 //15
		//LOG2_NUM_VOICES = 2, LOG2_NUM_SAMPLES_PER_VOICE = 1, NUM_ACCS = 4, ROT_BACK = 1, ROT_SWITCH_STEP = 1, ACC_BITS = 20 //15
	) (
		input wire clk, reset,

		output wire [IO_BITS-1:0] tx_pins,
		input wire [IO_BITS-1:0] rx_pins,

		output wire [7:0] ppu_ctrl,

		input wire ext_tx_request,
		//input wire [IO_BITS-1:0] ext_tx_data,
		//output wire ext_tx_scan, // ask for next data bits
		output wire ext_tx_ack
	);

	localparam WORD_SIZE = PAYLOAD_CYCLES * IO_BITS;
	localparam KEEPER_STATE_WORDS = (2**LOG2_NUM_VOICES - 1)*STATE_WORDS;

	wire new_sample, step_sample, ext_scan_accs, rewind_out_sample, inc_sweep_oct_counter, fir_enable;
	wire [NUM_OSCS-1:0] osc_enable;
	wire fir_done, sample_done;
	wire scan_ready = 1;

	wire fir_prepare;
	wire [$clog2(FIR_OUT_TAPS)-1:0] tap_pos;
	wire svf_enable;
	wire [`SVF_STEP_BITS-1:0] svf_step;
	wire [`LOG2_NUM_WFS-1:0] wf_index;

	wire out_valid;
	wire signed [PAYLOAD_CYCLES*IO_BITS-1:0] out;

	wire context_switch;
	wire [$clog2(STATE_WORDS + 1)-1:0] read_index, write_index;
	wire [IO_BITS-1:0] scan_in;
	wire [IO_BITS-1:0] scan_out;

	wire [PAYLOAD_CYCLES*IO_BITS-1:0] rx_buffer;
	wire sweep_data_valid;
	wire [$clog2(NUM_SWEEPS)-1:0] sweep_index;

	subsamp_voice #(.ACC_BITS(ACC_BITS), .NUM_ACCS(NUM_ACCS), .NUM_OSCS(NUM_OSCS), .FIR_OUT_TAPS(FIR_OUT_TAPS)) voice (
		.clk(clk), .reset(reset),
		.new_sample(new_sample), .step_sample(step_sample), .ext_scan_accs(ext_scan_accs), .rewind_out_sample(rewind_out_sample), .inc_sweep_oct_counter(inc_sweep_oct_counter),
		.osc_enable(osc_enable), .fir_enable(fir_enable),
		.fir_done(fir_done), .sample_done(sample_done),
		.fir_prepare(fir_prepare), .tap_pos(tap_pos), .svf_enable(svf_enable), .svf_step(svf_step), .wf_index(wf_index),
		.out_valid(out_valid), .out(out),
		//.scan(scan), .scan_in(scan_in), .scan_out(scan_out)
		.context_switch(context_switch),
		.read_index(read_index), .write_index(write_index),
		.rx_buffer(rx_buffer), .sweep_data_valid(sweep_data_valid), .sweep_index(sweep_index),
		.scan_in(scan_in), .scan_out(scan_out)
	);

	subsamp_voice_controller #(
		.LOG2_NUM_VOICES(LOG2_NUM_VOICES), .LOG2_NUM_SAMPLES_PER_VOICE(LOG2_NUM_SAMPLES_PER_VOICE), //.NUM_CONTEXT_CYCLES(`NUM_CONTEXT_CYCLES),
		.ROT_BACK(ROT_BACK), .ROT_SWITCH_STEP(ROT_SWITCH_STEP), .NUM_OSCS(NUM_OSCS), .FIR_OUT_TAPS(FIR_OUT_TAPS)
	) controller (
		.clk(clk), .reset(reset),
		.scan_ready(scan_ready),
		.new_sample(new_sample), .step_sample(step_sample), .ext_scan_accs(ext_scan_accs), .rewind_out_sample(rewind_out_sample), .inc_sweep_oct_counter(inc_sweep_oct_counter),
		.osc_enable(osc_enable), .fir_enable(fir_enable),
		.fir_done(fir_done), .sample_done(sample_done),
		.fir_prepare(fir_prepare), .tap_pos(tap_pos), .svf_enable(svf_enable), .svf_step(svf_step), .wf_index(wf_index),
		.out_valid(out_valid), .out(out),
		//.scan(scan)
		.context_switch(context_switch),
		.read_index(read_index), .write_index(write_index),
		.rx_buffer(rx_buffer), .sweep_data_valid(sweep_data_valid), .sweep_index(sweep_index),
		.scan_in(scan_in), .scan_out(scan_out),
		.tx_pins(tx_pins), .rx_pins(rx_pins),
		.ppu_ctrl(ppu_ctrl), .ext_tx_request(ext_tx_request), .ext_tx_ack(ext_tx_ack)
	);
endmodule
