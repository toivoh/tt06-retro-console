![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg)

AnemoneGrafx-8: Retro console in silicon with two parallax planes and analog emulation polysynth
================================================================================================
AnemoneGrafx-8 is a retro console in silicon, containing
- a PPU for VGA graphics output
- an analog emulation polysynth for sound output

The console is written for [Tiny Tapeout 06](https://tinytapeout.com).
The [Tiny Tapeout 06 Demo Board](https://tinytapeout.com/specs/pcb/) contains an RP2040 microcontroller. The RP2040 is intended to provide
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

For more details, see https://github.com/toivoh/tt06-retro-console/blob/main/docs/info.md.
