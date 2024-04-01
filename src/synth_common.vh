/*
 * Copyright (c) 2024 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`define NUM_CONTEXT_CYCLES 130
`define STATE_WORDS 9

`define SVF_STEP_BITS 2
`define LOG2_NUM_WFS  2

`define TX_SOURCE_BITS 2
// Scan data going out
`define TX_SOURCE_SCAN 2'd0
// Sample data going out
`define TX_SOURCE_OUT  2'd1
// Read address going out
`define TX_SOURCE_READ 2'd2

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
