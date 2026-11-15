## How it works

The Protocol Emulator is a chip that emulates digital communication protocols under
the control of a host. A host (for example the RP2350 on the Tiny Tapeout demo board)
talks to it over a 4-wire SPI link (mode 0, bytes MSB-first). Through that link the
host reads and writes the chip's internal registers, which configure and drive the
protocol engines on the `protocol in/out/io` pins.

Inside, four programmable sub-cores (in two pairs that can share program
memory) drive and sample the pins with clock-exact timing; a small main core with
a 512-word SRAM and a CRC / bit-stream unit frames and checks the data; a pin
layer maps 43 sources onto the 15 output pads and filters the 16 inputs. All
blocks share one system bus, on which the host has priority.

### Host link pins

| Pin | Signal | Direction |
|-----|--------|-----------|
| `ui[0]` | SCK | host -> chip |
| `ui[1]` | CS_n (active low) | host -> chip |
| `ui[2]` | MOSI | host -> chip |
| `uo[0]` | MISO | chip -> host |

`ui[3..7]`, `uo[1..7]` and `uio[0..7]` are reserved for the protocol engines.

## How to test

After reset every pad is released ('none': `uo_out` 0, `uio` inputs) and the
main core and sub-cores are halted. Bring-up is done by the host over SPI:
load the SRAM image, the sub-core programs and configuration, soft-reset the
sub-cores, write the pin map, then start the main core and the sub-cores
(architecture §6.5).

## External hardware

An SPI host, such as the RP2350 on the Tiny Tapeout demo board.
