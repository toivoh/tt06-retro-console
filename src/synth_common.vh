/*
 * Copyright (c) 2024 Toivo Henningsson <toivo.h.h@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

`define NUM_CONTEXT_CYCLES 130
`define STATE_WORDS 12

`define SVF_STEP_BITS 2
`define LOG2_NUM_WFS  2

`define TX_SOURCE_BITS 2
// Scan data going out
`define TX_SOURCE_SCAN 2'd0
// Sample data going out
`define TX_SOURCE_OUT  2'd1
// Read address going out
`define TX_SOURCE_READ 2'd2
// Other data going out
`define TX_SOURCE_EXT_OUT 2'd3


// Scan data coming back
`define RX_SB_SCAN  2'd1
// Read data coming back
`define RX_SB_READ  2'd2
// Write from the other side
`define RX_SB_WRITE 2'd3

// TODO: Suitable value?
`define REG_ADDR_BITS 4
`define REG_ADDR_SAMPLE_CREDITS 4'd0
`define REG_ADDR_SBIO_CREDITS   4'd1
`define REG_ADDR_PPU_CTRL       4'd2

`define PPU_CTRL_BIT_RST_N       3'd0
`define PPU_CTRL_BIT_SYNC_DATA   3'd1
`define PPU_CTRL_BIT_SEND_EVENTS 3'd2
`define PPU_CTRL_BIT_DITHER      3'd3
`define PPU_CTRL_BIT_RGB332_OUT  3'd4
`define PPU_CTRL_INITIAL         8'b01011
