<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## What it is

AnemoneGrafx-8 is a retro console containing

- a PPU for VGA graphics output
- an analog emulation polysynth for sound output

The design is intended to work together with the RP2040 microcontroller on the Tiny Tapeout 06 Demo Board, the RP2040 providing

- RAM emulation
- Connections to the outside world for the console (except VGA output)
- The CPU to drive the console

Features:

- PPU:
  - 320x240 @60 fps VGA output (actually 640x480 @60 VGA)
    - Some lower resolutions are also supported, useful if the design can not be clocked at 50.35 MHz
  - 16 color palette, choosing from 256 possible colors
  - Two independently scrolling tile planes
    - 8x8 pixel tiles
    - color mode selectable per tile:
      - 2 bits per pixel, using 4 subpalettes (selectable per tile)
      - 4 bits per pixel, halved horizontal resolution (4x8 stretched to 8x8 pixels)
  - 64 simultaneous sprites (more can be displayed at once with some Copper tricks)
    - mode selectable per sprite:
      - 16x8, 2 bits per pixel using 4 subpalettes (selectable per sprite)
      - 8x8, 4 bits per pixel
    - up to 4 sprites can be loaded and overlapping at the same pixel
      - more sprites can be visible on same scan line as long as they are not too cramped together
  - Simple Copper-like function for register control synchronized to pixel timing
    - write PPU registers
    - wait for x/y coordinate
- AnemoneSynth:
  - 16 bit 96 kHz output
  - 4 voices, each with
    - Two oscillators
      - Option to let the sub-oscillator generate noise
    - Three waveform generators with choice of sawtooth, triangle, pulse waves with 4 different duty cycles, 2 bit sawooth and triangle
    - 2nd order low pass filter
      - Sweepable volume, cutoff frequency, and resonance

## How it works

The console consists of two parts:

- The PPU generates a stream of pixels that can be output as a VGA signals, based tile graphics, map, and sprite data read from memory, and the contents of the palette registers.
- The synth generates a stream of samples by
	- context switching between voices at a rate of 96 kHz
		- adding the contributions for four 96 kHz samples from the voice to internal buffers in one go
	- outputting each 96 kHz sample once it has received contributions from each voice

### Using the PPU

	                index
	                depth,
	    sprite unit --->-\       index       rgb       rgb222
	        || |          compose --> palette -> dither----->-
	   tile map unit -->-/                                    \
	        || |    index, depth                               VGA ->
	       copper                                              out
	        |^ |   x, y                                       /
	        || +<---------raster scan -> delay ------------->-
	        V|                                hsync, vsync, active
	---> read unit --->
	data           addr

The PPU is composed of a number of components, including:

- The _sprite unit_ reads and buffers sprite data and sprite pixels, and outputs index and depth for the topmost sprite pixel
- The _tile map unit_ reads and buffers tilemap and tile pixel data,  and outputs index and depth for the topmost tile map pixel
- The _copper_ reads an instruction stream of register writes, wait for x/y, and jump instructions, and updates PPU registers accordingly
- The _read unit_ prioritizes read requests to graphics memory between the sprite unit, tile map unit, and copper, and keeps a track of the recipient of each data word when it comes back a number of cycles after the address was sent

The PPU uses 4 clock cycles to generate each pixel, which is duplicated into two VGA pixels of two cycles each.
(The two VGA pixels can be different due to dithering.)

Many of the registers and memories in the PPU are implemented as shift registers for compactness.

#### The read unit
The read unit transmits a sequence of 16 bit addresses, and expects to recieve the corresponding 16 bit data word after a fixed delay. In this way, it can address a 128 kB address space. The delay is set so that the tile map unit can request tilemap data, and receive it just in time to use it to request pixel data four pixels later.
The read unit transmits 4 address bits per cycle through the `addr_out` pins, and recieves 4 data bits per cycle through the `data_in` pins, completing one 16 bit read every _serial cycle_, which corresponds to one pixel or four clock cycles.

The tile map unit has the highest priority, followed by the copper, and finally the sprite unit, which is expected to have enough buffering to be able to wait for access. The tile map unit will only make accesses on every other serial cycle on average, and the copper at most once every few cycles, but they can both be disabled to give more bandwidth to the sprite unit.

#### The tile map unit
The tile map unit handles two independently scrolling tile planes, each composed of 8x8 pixel tiles.
The two planes get read priority on alternating serial cycles.
Each plane sends a read every four serial cycles, alternating between reading tile map data and the corresponding pixel data for the line.
The pixel data for each plane (16 bits) is stored in a shift register and gradually shifted out until the register can be quickly refilled. The sequencing of the refill operation is adjusted to provide one extra pixel of delay in case the pixel data arrives one pixel early (as it might have to do since the plane only gets read priority every other cycle).

#### The sprite unit
The sprite unit is the most complex part of the PPU. It works with a list of 64 sprites, and has 4 sprite buffers that can load sprite data for the current scan line. Once the final x coordinate of a sprite has passed, the corresponding sprite buffer can be reused to load a new sprite on the same line, as long as there is time to load the data before it should be displayed.

Sprite data is stored in memory in two structures:

- The sorted buffer
- The object attribute buffer

The sorted buffer must list all sprites to be displayed, sorted from left to right, with y coordinate and index. (16 bits/sprite)
The object attribute buffer contains all other object attributes: coordinates (only 3 lowest bits of y needed), palette, graphic tile, etc. (32 bits/sprite)

Sprite processing proceeds in three steps, each with its own buffers and head/tail pointers:

- Scan the sorted list to find sprites overlapping the current y coordinate (in order of increasing x value), store them in the id buffer (4 entries)
- Load object attributes for sprites in the id buffer, store in a sprite buffer and free the id buffer entry (4 sprite buffers)
- Load sprite pixels for sprites in the sprite buffer

Each succeeding step has higher priority to access memory, but will only be activated when the preceeding step can feed it with input data.

Pixel data for each sprite buffer is stored in a 32 bit shift register, and gradually shifted out as needed. If sprite pixels are loaded after the sprite should start to be displayed, the shift register will catch up as fast as it can before starting to provide pixels to be displayed. This will cause the leftmost pixels of the sprite to disappear (or all of them, if too many sprites are crowded too close).

### Synth

	    phase      phase      sample        sample      sample
	main                 wave-
	osc  --> linear      form       state         FIR         output
	         combin- ==> gene- ===> variable ---> down-  ---> buffer
	sub  --> ations      rators     filter        sampling
	osc                                           filter

The synth has 4 voices, but there is only memory for one voice at a time; the synth makes frequent context switches between the voices to be able to produce an output signal that contains the sum of the outputs.
Each voice contributes four 96 kHz time steps worth of data to the output buffer before being switched out for the next.
As soon as all voices have contibuted to an output buffer entry, it is fed to the output, and the space is reused for a new entry.

The synth is nominally sampled at 3072 kHz to produce output samples at a rate of 96 kHz. The high sample rate is used so that the main oscillator can always produce a an output that is exactly periodic with a period corresponding to the oscillator frequency, while maintaing good frequency resolution (< 1.18 cents at up to 3 kHz).
The 32x downsampling is done with a 96 tap FIR filter, so that each input sample contributes to three output samples.
Th FIR filter is optimized to minimize aliasing in the 0 - 20 kHz range after the 96 kHz output has been downsampled to 48 kHz with a good external antialiasing filter, assuming that the input is a sawtooth wave of 3 kHz or less.

To reduce computations, most of samples that a voice would feed into the FIR filter are zeros.
Usually, the voice steps 8 samples at a time, adding a single nonzero sample. Seen from this perspective, each voice is sampled at 384 kHz. This is just enough so that the state variable filter appears completely open when the cutoff frequency is set to the maximum.

To maintain frequency resolution, the main oscillator can periodically take a step of a single 3072 kHz sample, to pad out the period to the correct length. This results in advancing the state variable filter an eigth of a normal time step, and sending an output sample with an eigth of the normal amplitude through the FIR filter.
The sub-oscillator does not have the same independent frequency resolution since it does not control the small steps, but is often used at a much lower frequency.

The state variable filter is implemented using the same ideas as described and used in https://github.com/toivoh/tt05-synth, using a shift-adder for the main computations. The shift-adder is also time shared with the FIR filter; each FIR coefficient is stored as a sum / difference of powers of two (the FIR table was optimized to keep down the number of such terms). The shift-adder saturates the result if it would overflow, which allows to overdrive the filter.

Each oscillator uses a phase of 10 bits. A clock divider is used to get the desired octave.
To get the desired period, the phase sometimes needs to stay on the same value for two steps.
To choose which steps, the phase value is bit reversed and compared to the mantissa of the oscillators period value (the exponent controls the clock divider). This way, only a single additional bit is needed to keep track of the oscillator state beyond the current phase value.

Each time a voice is switched in, five sweep values are read from memory to decide if the two frequencies and 3 control periods for the state variable filters (see https://github.com/toivoh/tt05-synth) should be swept up or down. A similar approach is used as above, with a clock divider for the exponent part of the sweep rate, and bit reversing the swept value to decide whether to take a small or a big step.

## IO interfaces
AnemoneGrafx-8 has four interfaces:

- VGA output `uo` / `(R1, G1, B1, vsync, R0, G0, B0, hsync)`
- Read-only memory interface `(addr_out[3:0], data_in[3:0])` for the PPU
- Memory/host interface `(tx_out[1:0], rx_in[1:0])` for the synth, system control, and vblank events
	- `rx_in[1:0] = uio[7:6]` can be remapped to `rx_in_alt[1:0] = ui[5:4]` to free up `uio[7:6]` for use as outputs
- Additional video outputs `(Gm1_active_out, RBm1_pixelclk_out)`. Can output either
	- Additional lower `RGB` bits to avoid having to dither the VGA output
	- Active signal and pixel clock, useful for e g HDMI output

Additionally

- `data_in[0]` is sampled into `cfg[0]` as long as `rst_n` is high to choose the output mode
	- `cfg[0] = 0`: `uio[7:6]` is used to input `rx_in[1:0]`,
	- `cfg[0] = 1`: `uio[7:6]` is used to output `{RBm1_pixelclk_out, Gm1_active_out}`.
- When the PPU is in reset (due to `rst_n` or `ppu_rst_n`), `addr_out` loops back the values from `data_in`, delayed by two register stages.

### VGA output
The VGA output follows the [Tiny VGA pinout](https://tinytapeout.com/specs/pinouts/#vga-output), giving two bits per channel.
The PPU works with 8 bit color:

	R = {R1, R0, RBm1}
	G = {G1, G0, Gm1}
	B = {B1, B0, RBm1}

where the least significant bit it is identical between the red and blue channel.
By default, dithering is used to reduce the output to 6 bit color (two bits per channel).
Dithering can be disabled, and the low order color bits `{RBm1, Gm1}` be output on `{RBm1_pixelclk_out, Gm1_active_out}`.

The other output option for `(Gm1_active_out, RBm1_pixelclk_out)` is to output the `active` and `pixelclk` signals:

- `active` is high when the current RGB output pixel is in the active display area.
- `pixelclk` has one period per VGA pixel (two clock cycles), and is high during the second clock cycle that the VGA pixel is valid.

### Read-only memory interface
The PPU uses the read-only memory interface to read video RAM. The interface handles only reads, but video RAM may be updated by means external to the console (and needs to, to make the output image change!).

Each read sends a 16 bit word address and receives the 16 bit word at that address, allowing the PPU to access 128 kB of data.
A read occurs during a _serial cycle_, or 4 clock cycles. As soon as one serial cycle is finished, the next one begins.

The address `addr[15:0]` for one read is sent during the serial cycle in order of lowest bits to highest:

	addr_out[3:0] = addr[3:0]   // cycle 0
	addr_out[3:0] = addr[7:4]   // cycle 1
	addr_out[3:0] = addr[11:8]  // cycle 2
	addr_out[3:0] = addr[15:12] // cycle 3

The corresponding `data[15:0]` should be sent in the same order to `data_out[3:0]` with a specific delay that is approximately three serial cycles (TODO: describe the exact delay needed!).
The `data_in` to `addr_out` loopback function has been provided to help calibrate the required data delay.

To respond correctly to reads requests, one must know when a serial cycle starts.
This accomplished by an initial synchronization step:

- After reset, `addr_pins` start at zero.
- During the first serial cycle, a fixed address of `0x8421` is transmitted, and the corresponding data is discarded

### Memory / host interface
The memory / host interface is used to send a number of types messages and responses.
It uses start bits to allow each side to initiate a message when appropriate, subsequent bits are sent on subsequent clock cycles.
`tx_out` and `rx_in` are expected to remain low when no messages are sent.

`tx_out[1:0]` is used for messages from the console:

- a message is initiated with one cycle of `tx_out[1:0] = 1` (low bit set, high bit clear),
- during the next cycle, `tx_out[1:0]` contains the 2 bit _tx header_, specifying the message type,
- during the following 8 cycles, a 16 bit payload is sent through `tx_out[1:0]`, from lowest bits to highest.

`rx_in[1:0]` is used for messages to the console:

- a message is initiated with one cycle when `rx_in[1:0] != 0`, specifying the _rx header_, i e, the message type
- during the following 8 cycles, a 16 bit payload is sent through `rx_in[1:0]`, from lowest bits to highest.

TX message types:

- 0: Context switch: Store payload into state vector, return the replaced state value (rx header=1), increment state pointer.
- 1: Sample out: Payload is the next output sample from the synth, 16 bit signed.
- 2: Read: Payload is address, return corresponding data (rx header=2).
- 3: Vblank event. Payload should be ignored.

The state pointer should wrap after 36 words.

RX message types:

- 1: Context switch response.
- 2: Read response.
- 3: Write register. Top byte of payload is register address, bottom is data value.

Available registers:

- 0: `sample_credits` (initial value 1)
- 1: `sbio_credits` (initial value 1)
- 2: `ppu_ctrl` (initial value `0b01011`)

TODO: Describe the registers!

## Using the PPU
The PPU is almost completely controlled through the VRAM (video RAM) contents.
The copper is restarted when a new frame begins, and starts to read instructions at address `0xfffe`. Copper instructions can write PPU registers; using the copper is the only way to write and initialize these registers.

The PPU registers in turn control the display of tile planes and sprites.

### PPU registers
The PPU has 32 PPU registers, which control different aspects of its operation.
Each register has up to 9 bits. The registers are laid out as follows:

	Address Category    Contents
	                      8    7    6    5    4    3    2    1    0
	 0 - 15 pal0-pal15 | r2   r1   rb0  g2   g1   g0   b2   b1  | X |
	16      scroll     |      scroll_x0                             |
	17      .          |  X | scroll_y0                             |
	18      .          |      scroll_x1                             |
	19      .          |  X | scroll_y1                             |
	20      copper_ctrl|      cmp_x                                 |
	21      .          |      cmp_y                                 |
	22      .          |      jump_low                              |
	23      .          |      jump_high                             |
	24      base_addr  |      base_sorted                           |
	25      .          |      base_oam                              |
	26      .          |      base_map1    |      base_map0     | X |
	27      .          |      X            |b_tile_s | b_tile_p | X |
	28      gfxmode1   |      r_xe_hsync             | r_x0_fp      |
	29      gfxmode2   |vpol|hpol|  vsel   |      r_x0_bp           |
	30      gfxmode3   |      xe_active                             |
	31      displaymask|      X       |lspr|lpl1|lpl0|dspr|dpl1|dpl0|

where `X` means that the bit(s) in question are ignored.

Initial values:

- The `gfxmode` registers are initialized to `320x240` output (640x480 VGA output; pixels are always doubled in both directions before VGA output).
- The `displaymask` register is initialized to load and display sprites as well as both tile planes (initial value `0b111111`).
- The other registers, except the `copper_ctrl` category, need to be initialized after reset.

Each PPU register is described in the appropriate section:

- Palette (`pal0-pal15`)
- Tile planes (`scroll`, `base_map0`, `base_map1`, `b_tile_p`, `lpl0`, `lpl1`, `dpl0`, `dpl1`)
- Sprites (`base_sorted`, `base_oam`, `b_tile_s`, `lspr`, `dspr`)
- Copper (`copper_ctrl`)
- Graphics mode `gfxmode1-gfxmode3`)

### Palette
The PPU has a palette of 16 colors, each specified by 8 bits, which map to a 9 bit RGB333 color according to

	R = {r2, r1, rb0}
	G = {g2, g1, g0}
	B = {b2, b1, rb0}

where the least significant bit is shared between the red and blue channels.
Each palette color is set by writing the corresponding `palN` register. The instant when a palette color register is written, its color value will be used to display the current pixel if it is inside the active display area.

Tile and sprite graphics typically use 2 bits per pixel. They have a 4 bit `pal` attribute that specifies the mapping from tile pixels to paletter colors according to:

    pal     color 0     color 1     color 2     color 3
      
      0           0           1           2           3
      4           4           5           6           7
      8           8           9          10          11
     12          12          13          14          15
      
      2           2           3           4           5
      6           6           7           8           9
     10          10          11          12          13
     14          14          15           0           1
      
      1           0           4           8          12
      5           1           5           9          13
      9           2           6          10          14
     13           3           7          11          15
      
      3           8          12           1           5
      7           9          13           2           6
     11          10          14           3           7
      
     15 ---------------- 16 color mode ----------------

_Note that color 0 is transparent unless the `always_opaque` bit of the sprite/tile is set._
If no tile or sprite covers a given pixel, palette color 0 is used as background color.

In 16 color mode, two horizontally consecutive 2 bit pixels are used to form one 4 bit pixel.

- For 16 color tiles, each pixel is twice as wide to preserve the same total width.
- 16 color sprites are half as wide (8 pixels instead of 16).

### Tile graphic format
Tile planes and sprites are based on 8x8 pixel graphic tiles with 2 bits/pixel.
Each graphic tile is stored in 8 consecutive 16 bit words; one per line.
Within each line, the first pixel is stored in the bottom two bits, then the next pixel, and so on.

### Tile planes
The PPU supports two independently scrolling tile planes. Plane 0 is in front of plane 1.
Four `display_mask` bits control the behavior of the tile planes:

- When `dpl0` (`dpl1`) is cleared, plane 0 (1) is not displayed.
- When `lpl0` (`lpl1`) is cleared, no data for plane 0 (1) is loaded.

If a planes is not to be displayed, its `lplN` bit can be cleared to free up more read bandwidth for the sprites and copper. The plane's `lplN` bit should be set at least 16 pixels before the plane should be displayed.

The VRAM addresses used for the tile planes are

	plane_tiles_base = b_tile_p  << 14
	map0_base        = base_map0 << 12
	map1_base        = base_map1 << 12

The `scroll` registers specify the scroll position of the respective plane (TODO: describe offset).

The tile map for each plane is 64x64 tiles, and is stored row by row.
Each map entry is 16 bits:

	  15 - 12        11         10   -   0
	| pal     | always_opaque | tile_index |

where the tile is read from word address

	tile_addr = plane_tiles_base + (tile_index << 3)

### Sprites
Each sprite can be 16x8 pixels (4 color) or 8x8 pixels (16 color).
The PPU supports up to 64 simultaneous sprites in oam memory, but only 4 can overlap at the same time. Once a sprite is done for the scan line, the PPU can load a new sprite into the same slot, to display later on the same scan line, but it takes a number of pixels (partially depending on how much memory traffic is used by the tile planes and the copper.) More than 64 sprites can be displayed in a single frame by using the copper to change base addresses mid frame.

Two `display_mask` bits control the behavior of the sprite display:

- When `dspr` is cleared, no sprites are displayed.
- When `lspr` is cleared, no data for sprites is loaded.

It will take some time `lspr` is set before new sprites are completely loaded and can be displayed.

The VRAM addresses used for sprite display are

	sprite_tiles_base = b_tile_s    << 14
	sorted_base       = base_sorted <<  6
	oam_base          = base_oam    <<  7

Sprites are described by two lists, each with 64 entries:

- The _sorted list_ lists sprites in order of increasing x coordinates.
- _Object Attribute Memory_ (OAM) defines most properties for the sprites.

To display sprites correctly, they must be listed in the sorted list in order of increasing x coordinate, starting from `sorted_base`.
Each entry in the sorted list is 16 bits:

	  15   14   13 - 8   7 - 0
	| m1 | m0 |  index |   y   |

where

- `y` is the sprite's y coordinate,
- `index` is the sprite's index in OAM,
- `m0` (`m1`) hides the sprite on even (odd) scan lines if it is set. (Each output pixel is displayed on two VGA scan lines.)

If there are less than 64 sprites to be displayed, the remaining sorted entries should be masked by setting `m0` and `m1`, or moving the sprite to a y coordinate where it is not displayed.

For each sprite, OAM contains two 16 bit words `attr_y` and `attr_x`, which define most of the sprite's properties. `attr_y` for sprite 0 is stored first, followed by `attr_x`, then the same for sprite 1, 2, etc.
The contents are

	attr_y:  15 14   13   -   4   3   2 - 0
	       |   X   | tile_index | X | ylsb3 |

	attr_x:  15 - 12        11         10 - 9   8 - 0
	       |   pal   | always_opaque |  depth |   x   |

where

- the sprite's graphics are fetched from the two consecutive graphic tiles starting at `sprite_tiles_base + (tile_index << 4)`,
- `ylsb3` is the 3 lowest bits of the sprite's y coordinate,
- `pal` and `always_opaque` work as described in the Palette section,
- `depth` specifies the sprite's depth relative to the tile planes,
- `x` is the sprite's x coordinate.

If several visible sprites overlap, the lowest numbered sprite with an opaque pixel wins.
The `depth` value then decides whether that is displayed in front of the tile planes:

- 0: In front of both tile planes.
- 1: Behind plane 0, in front of plane 1.
- 2: Behind both tile planes.
- 3: Not displayed.

A sprite with a `depth` value of 3 will block sprites with higher index from being displayed in the same location. If a sprite should be hidden but does not need to block other sprites in this manner, omit it from the sorted list instead.

TODO: Describe sprite coordinate offsets.

### Copper
The copper executes simple instructions, which can

- write to PPU registers,
- wait until a given raster position is reached,
- jump to continue copper execution at a different VRAM location, or
- halt the copper until the beginning of the next frame.

The copper is restarted each time a new frame begins, just after the last active pixel of the previous frame has been displayed. It always starts at VRAM location `0xfffe`, with `fast_mode = 0`.

Each copper instruction is 16 bits:

	  15 - 7 |     6       5 - 0
	|  data  | fast_mode |  addr |

where

- `data` specifies the data to be written to a PPU register,
- `fast_mode` enables the copper to run 3 times as fast, but is incompatible with waiting and jumping,
- `addr` specifies the PPU register to be written (see PPU registers).

The copper halts if it receives an instruction with `addr = 0xb111111`, otherwise it writes `data` to the PPU register given by `addr`, if one exists.

The `copper_ctrl` PPU registers have specific effects on the copper:
#### Compare registers
Writing a value to `cmp_x` or `cmp_y` causes the copper to delay the next write until the specified compare value is >= to the specified x or y raster position.
TODO: Describe mapping of raster position to `cmp_x` and `cmp_y`.

#### Jumps
Usually, the copper loads instructions from consecutive addresses.
A sequence of two instructions is needed to execute a jump:

- First, write the low byte of the jump address to `jump_low`.
- Then, write the high byte of the jump address to `jump_high`. The jump is executed.

There should be no writes to `cmp_x` or `cmp_y` between these two instructions, as the the `cmp` register is used to store the low byte of the jump address while waiting for the write to `jump_high`.

#### Fast mode
Each time an instruction arrives at the copper, the value of `fast_mode` in the instruction overwrites the current value.
When `fast_mode = 0`, the copper does not start to read a new instruction until the previous instruction has finished. This allows waiting for compare values and jumping to work as intended.
When `fast_mode = 1`, the copper can send a new read every other serial cycle (unless blocked by reads from the tile planes, which have higher priority), queuing up several reads before the instruction data from the first one arrives. This can allow the copper to work up to 3 times as fast, and works as intended as long as no writes are done to the `copper_ctrl` registers.

The `fast_mode` bit

- Should be set to zero
	- at least three instructions before a write to any of the `copper_ctrl` registers,
	- for instructions that follow a write to `cmp_x` or `cmp_y`.
- Can be set to one by an instruction that writes to `jump_high` (but not the other `copper_ctrl` registers) unless it needs to be zero due to the above.

### Graphics mode registers
The `gfxmode` registers allow to change the timing of the VGA raster scan.
The horizontal timing can be changed in fine grained steps, while the vertical timing supports 3 options.

The intention of the `gfxmode` registers is to support output in the VGA modes

	640x480 @ 60 Hz
	640x400 @ 70 Hz
	640x350 @ 70 Hz

The visual output resolution will be halved in both directions, by doubling the pixels.

These VGA modes are all based on a pixel clock of 25.175 MHz, which can be achieved if the console is clocked at twice the pixel clock, or 50.35 MHz. (VGA monitors should be quite tolerant of deviations around this frequency, 50.4 MHz should be fine and can be achieved with the RP2040 PLL.)

The intention is also to support reduced horizontal resolution while generating a VGA signal according to one of these modes, in case the console has to be clocked at a lower frequency. This will lower the output frequency that can be achieved by the synth as well.

#### Vertical timing
The `vsel` bits select between vertical timing options:

		   VGA     PPU pixel
	vsel   lines   rows                         recommended polarity
	   0     480     240                        vpol=1, hpol=1
	   1      64      32  test mode (not VGA)   -
	   2     400     200                        vpol=0, hpol=1
	   3     350     175                        vpol=1, hpol=0

The `hpol` and `vpol` bits control the sync polarity (0=positive, 1=negative). Original VGA monitors may use these to distinguish between modes; modern monitors should be able to detect the mode from the timing.

#### Horizontal timing
Possible horizontal timings include

	VGA        PPU pixel
	columns    columns    PPU clock    gfxmode1  gfxmode2  gfxmode3
	    640        320    50.35  MHz     0x0178    0x0188    0x01bf
	    424        212    33.57  MHz     0x00f9    0x0190    0x0153
	    416        208    33.57  MHz     0x00f8    0x018d    0x014f
	    320        160    25.175 MHz     0x00bc    0x0194    0x011f

where the `vsel`, `hpol`, and `vpol` bits have been set to 480 line mode, but this can be easily changed by updating the `gfxmode2` value.
The 416 column mode is a tweak on the 424 column mode to fit a whole number of tiles (26) in the horizontal direction. In 424 and 416 column mode, one PPU pixel should be stretched to 3 VGA pixels horizontally, and in 320 column mode, it should be stretched to 4.

The "PPU clock" column lists the recommended clock frequency to feed the console in order to achieve the 60 fps (640x480 modes) or 70 fps (640x400 and 640x350 modes).
In practice, VGA monitors seem quite tolerant of timing variations, and might, e g, accept a 640x480 signal at down to 2/3 of the expected clock rate.

The `gfxmode` registers control the horizontal timing accordigng to

	active:      xe_active - 127  PPU pixels
	front porch: 8  - r_x0_fp     PPU pixels
	hsync:        1 + r_xe_hsync  PPU pixels
	back porch:  32 - r_x0_bp     PPU pixels

where `xe_active` must be >= 128.

### Using AnemoneSynth
AnemoneSynth is a synth with four voices, each with 

- two oscillators (main and sub),
- three waveform generators,
- a second order filter.

The synth is designed for an output sample rate `output_freq` of 96 kHz (higher sample rates are used in intermediate steps), which should be achievable if the console is clocked at close to the target frequency of 50.34 MHz. The user of the synth can reduce `output_freq` by requesting output samples less frequently.

The hardware processes one voice at a time, and periodically performs a context switch to write the state of the active voice out to RAM and read in the state for the next active voice.
The voice state is divided into dynamic state (updated by the synth) and parameters (not updated by the) synth. Much of the behavior of a voice can be controlled through its parameters.

The state of a voice also includes the frequencies of its two oscillators, and three control frequencies controlling the filter. This is dynamic state, because it can be updated according to sweep parameters, specifiying a certain rate of rise or fall. Sweep parameters are not stored in the voice state, but are read from RAM as needed to update the frequencies. Envelopes can be realized by changing sweep parameters over time.

#### Voice state
The voice state consists of twelve 16 bit words:

	bit       bit
	address   width   name
	      0       1   delayed_s
	      1       2   delayed_p
	      3       3   fir_offset_low
	      6      10   phase[0]
	     16      10   phase[1]
	     26       6   running_counter
	     32      20   y
	     52      20   v
	     72      14   float_period[0]   main oscillator period
	     86      14   float_period[1]   sub-oscillator period
	    100      10   mod[0]            control period 0
	    110      10   mod[1]            control period 1
	    120      10   mod[2]            control period 2
	    130       5   lfsr_extra
	    135       1   ringmod_state

	    136      13   wf_params[0]      waveform 0 parameters
	    149      13   wf_params[1]      waveform 1 parameters
	    162      13   wf_params[2]      waveform 2 parameters
	    175      13   voice_params      voice parameters
	    188       4   unused

The dynamic part of the state contains many things, but the parts the need to be controlled use the synth are primarily `float_period` and `mod` fields, which can be set and swept through the sweep parameters.
The parameter part of the state begins at `wf_params[0]`.

There are three sets of waveform parameters `wf_params`, each consisting of 13 bits:

	bit       bit
	address   width   name         default
	      0       3   wf
	      3       2   phase0_shl         0
	      5       2   phase1_shl         0
	      7       2   phase_comb         0/1/2 for waveform 0/1/2
	      9       2   wfvol              0
	     11       1   wfsign             0
	     12       1   ringmod            0

The voice parameters `voice_params` also consist of 13 bits:

	bit       bit
	address   width   name             default
	      0       1   lfsr_en                0
	      1       2   filter_mode            0
	      3       3   bpf_en                 0
	      6       1   hardsync               0
	      7       4   hardsync_phase         0
	     11       2   vol                    0

#### Frequency representation
Frequencies are represented by periods in a kind of floating point format, with 4 bits to set the octave, and 10 or 6 bits to set the mantissa:

	{oct[3:0], mantissa[9:0]} = float_period[i]  // for oscillator periods
	{oct[3:0], mantissa[5:0]} = mod[i]           // for control periods

The period value is calculated as

	osc_period[i] = (1024 + mantissa) << oct     // for oscillator periods
	mod_period[i] =   (64 + mantissa) << oct     // for control periods

except that `oct = 15` corresponds to an infinite period, or a frequecy of zero.
The oscillator frequencies are given by

	osc_freq[i] = output_freq * 32 / osc_period[i]

so at `output_freq = 96 kHz`, the highest achievable oscillator frequency is 3 kHz (and the lowest is a bit below 0.1 Hz).
The control frequencies are given by

	mod_freq[i] = output_freq * 256 / mod_period[i]

#### Signal path
The signal path starts at the two oscillators, which feed 3 waveform generators. Each waveform generator can be fed with a different linear combination of oscillator phases. The waveforms are fed into the filter. Finally, the output of the filter is summed for all the voices to create the synth's output signal.

##### Oscillators
The main and sub-oscillators both produce sawtooth waves as output.
When we talk about phase, it refers to such a sawtooth value, increasing at a constant rate over the period, and wrapping once per period.
The sub-oscillator can produce noise instead by setting `lfsr_en=1`. (TODO: Describe noise frequency dependence on `osc_period[1]`.)

The main oscillator is intended to be set voice's current pitch (or possibly the pitch divided by a small integer). This makes the voice's supersampling and antialiasing produce the best result, to avoid aliasing artifacts, especially for high pitched voices.

If the voice's output signal is periodic with the main oscillator's period, there should be very little aliasing artifacts. If the output waveform varies slowly when the voice output is chopped up into periods equal to the main oscillator period, there should still be little aliasing.

The sub-oscillator has lower frequency resolution than the main oscillator in the highest octaves: 1 bit less when `oct=2`, 2 bits less when `oct=1`, and 3 bits less when `oct=3`.
The simplest use of the sub-oscillator is to set it to a frequency of maybe 1/1000 of the main oscillator frequency, and use three waveforms with `main + sub`, `main`, and `main - sub` to get a detuning effect.
Higher frequency compared to the main oscillator gives more detuning.

The sub-oscillator can be hard-synced to the main oscillator by setting `hardsync=1`.
When enabled, the phase of the sub-oscillator resets to `hardsync_phase << 6` whenever the main oscillator completes a period.

##### Combining the oscillators
The `phase_comb`, `phase0_shl` and `phase1_shl` of each waveform specify how to calculate the waveform generator's input phase from the oscillator phases.
The `phase_comb` parameter selects between four modes:

	phase_comb 		phase
			 0 		(main << phase0_shl) + (sub << phase1_shl)
			 1 		(main << phase0_shl) - (sub << phase1_shl)
			 2 		(main << phase0_shl)
			 3 		                       (sub << phase1_shl)

A good default is to set `phase_comb` to 0 for one waveform, 1 for one, and 2 for one, leaving the other waveorm parameters the same. Combined with a sub-oscillator at around a 1/1000 of the main oscillator frequency, this creates a detuning effect.

##### Waveform generator
The `wf` parameter selects between 8 wave forms:

	wf    waveform
	 0    sawtooth wave
	 1    sawtooth wave, 2 bit
	 2    triangle wave
	 3    triangle wave, 2 bit
	 4    square wave
	 5    pulse wave, 37.5% duty cyckle
	 6    pulse wave, 25%   duty cyckle
	 7    pulse wave, 12.5% duty cyckle

All waveforms have a zero average level. The peak-to-peak amplitude of the pulse waves is half that of the other waveforms.

The waveform amplitude is multiplied by `2^-wfvol`. If `wfsign=1`, it is inverted.
If `wfvol=3, wfsign=1`, the waveform is silenced.

If `ringmod=1`, the waveform is inverted when the output of the previous waveform generator is negative before the effects of `wfvol`, `wfsign`, and `ringmod` have been applied (waveform 2 is previous to waveform 0).

##### Filter
The output from each waveform generator is fed into the filter.
The `filter_mode` parameters selects the filter type:

	filter_mode
	          0   2nd order filter
	          1   2nd order filter, transposed
	          2   2nd order filter, two volumes, default damping
	          3   Two cascaded 1st order filters

The `mod` interpretation of the mod states depends on the filter mode:

	filter_mode   mod[0]   mod[1]   mod[2]
	          0   cutoff   fdamp    fvol
	          1   cutoff   fdamp    fvol
	          2   cutoff   fvol2    fvol
	          3   cutoff   cutoff2  fvol

The transposed filter mode 1 is expected to be a bit noisier than the default mode 0, and have somewhat different overdrive behavior.
Howerver, in filter modes 1 and 3, `bpf_en[i]` can be used to change the point where waveform `i` feeds into the filter:

- For `filter_mode=1`,  `bpf_en[i]=1` makes the filter behave as a band pass filter for that waveform.
- For `filter_mode=3`,  `bpf_en[i]=1` feeds the waveform straight into the second low pass filter.

The volume feeding into the filter is generally given by 

	gain = fvol / cutoff

but for `filter_mode=3`,

- `fvol2` is used instead of `fvol` for waveform 1,
- `cutoff2` is used instead of `cutoff` when  `bpf_en[i]=1`.

It is possible to overdrive the filter, which will saturate. This can be a desirable effect.

For filter modes 0-2, the filter cutoff frequency is given by

	cutoff_freq = cutoff / (2*pi)

For filter mode 3, it is given by `cutoff` (TODO: check).

Filter modes 0 and 1 implement resonant filters, the resonance is given by

	Q = cutoff / f_damp

where the resonance can start to be noticeable when `Q` becomes > 1.

##### Output
The filter output from each voice is multiplied by `2^(-vol)` and then these contributions are added together to from the synth's output.

### Sweeps
Each voice has five sweep values, which can be used to sweep the oscillaror and control frequencies gradually up or down, or set them to new values without interfering with synth's state updates.

Each sweep value is a 16 bit word.
A voice will periodically send read messages (tx header = 2) to read its sweep values, with

	address = (voice_index << 3) + sweep_index

where `sweep_index` describes the target of the sweep value:

	sweep_index   target
			  0   float_period[0]
			  1   float_period[1]
			  2   mod[0]
			  3   mod[1]
			  4   mod[2]

The sweep value can have two formats:

	 15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
	| X | 0 | replacement value                                    |
	| X | 1 | X        |sign| oct           | mantissa             |

In the first case, the target value is simply replaced. For `mod` targets, the lowest four bits of the replacement value are discarded.

In the second case, the target is incremented (`sign=0`) or decremented (`sign=1`) at a rate that is described by `oct` and `mantissa` which are arranged in the same kind of simple floating point format as is used for `mod` values.
The maximum that the target can be incremented or decremented by one is `output_freq / 2`, achieved when `oct` and `mantissa` are zero. In general, the sweep rate is

	sweep_rate = 32 * output_freq / ((64 + mantissa) << oct)

Sweeping will never cause the target value to wrap around, but may cause it to stop a single step short of the extreme value.
When `oct=15`, no sweeping will occur. This can be accomplished by setting the sweep value to all ones.

## How to test

TODO

## External hardware

A PMOD for VGA is needed for video output, that can accept VGA output according to https://tinytapeout.com/specs/pinouts/#vga-output.
Means of sound output is TBD, a PMOD for I2S might be needed (if so, haven't decided which one to use yet).
The RP2040 receives the sound samples, and could alternatively output them in some other way.
