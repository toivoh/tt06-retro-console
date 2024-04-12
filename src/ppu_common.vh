/*
 * Copyright (c) 2024 Toivo Henningsson <toivo.h.h@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

`define I_HSYNC 0
`define I_VSYNC 1
`define I_ACTIVE 2
`define I_ACTIVE_OR_BP 3
`define I_NEW_LINE 4
`define I_NEW_FRAME 5
`define I_LAST_PIXEL 6
`define I_V_ACTIVE 7
`define I_LAST_PIXEL_GROUP 8
`define NUM_SCAN_FLAGS 9

//`define REGISTER_RASTER_SCAN

// All horizontal parameters are assumed to have an active width that is a multiple of four.
// Clearing of levels_sreg at the end of a scan line relies on this.

`define HPARAMS_160 {9'd128 - 9'd4, 9'd127 + 9'd24, 9'd128 - 9'd12, 9'd127 + 9'd160} //160xH
`define HPARAMS_208 {9'd128 - 9'd9, 9'd127 + 9'd32, 9'd128 - 9'd18, 9'd127 + 9'd208} //208xH
`define HPARAMS_212 {9'd128 - 9'd7, 9'd127 + 9'd32, 9'd128 - 9'd16, 9'd127 + 9'd212} //212xH
//`define HPARAMS_213 {9'd128 - 9'd6, 9'd127 + 9'd32, 9'd128 - 9'd16, 9'd127 + 9'd213} //213xH
`define HPARAMS_240 {9'd128 - 9'd6, 9'd127 + 9'd36, 9'd128 - 9'd18, 9'd127 + 9'd240} //240xH
`define HPARAMS_320 {9'd128 - 9'd8, 9'd127 + 9'd48, 9'd128 - 9'd24, 9'd127 + 9'd320} //320xH

`define HPARAMS_280 {9'd128 - 9'd7, 9'd127 + 9'd42, 9'd128 - 9'd21, 9'd127 + 9'd280} //280xH
`define HPARAMS_360 {9'd128 - 9'd9, 9'd127 + 9'd54, 9'd128 - 9'd27, 9'd127 + 9'd360} //360xH


`define VPARAMS_480    {9'd479,  9'd9, 9'd1, 9'd32} // Wx480
`define VPARAMS_240_b8 {8'd239,  8'd4, 8'd0, 8'd16} // Wx240 = Wx480 halved with bp rounded up

`define VPARAMS_400    {9'd399, 9'd11, 9'd1, 9'd34} // Wx400
`define VPARAMS_200_b8 {8'd199, 8'd05, 8'd0, 8'd17} // Wx200 = Wx400 halved with bp rounded up

`define VPARAMS_350    {9'd349, 9'd36, 9'd1, 9'd59} // Wx350
`define VPARAMS_175_b8 {8'd174, 8'd18, 8'd0, 8'd29} // Wx175 = Wx350 halved with fp rounded up


// For testing
`define VPARAMS_64_TEST {9'd63,  9'd1, 9'd0,  9'd2}
