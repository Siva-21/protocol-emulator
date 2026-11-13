## How it works

The Protocol Emulator is a chip that emulates digital communication protocols under
the control of a host. A host (for example the RP2350 on the Tiny Tapeout demo board)
talks to it over a 4-wire SPI link (mode 0, bytes MSB-first). Through that link the
host reads and writes the chip's internal registers, which configure and drive the
protocol engines on the `protocol in/out/io` pins.

**Design in progress:** this version is a placeholder top. While `ena` is high it
registers `ui_in XOR uio_in` onto `uo_out` (so every input is used); `uio` is unused
(all inputs, `uio_out` and `uio_oe` driven low). The host link and protocol engines
are not included yet.

### Host link pins

| Pin | Signal | Direction |
|-----|--------|-----------|
| `ui[0]` | SCK | host -> chip |
| `ui[1]` | CS_n (active low) | host -> chip |
| `ui[2]` | MOSI | host -> chip |
| `uo[0]` | MISO | chip -> host |

`ui[3..7]`, `uo[1..7]` and `uio[0..7]` are reserved for the protocol engines.

## How to test

Not functional yet. With `ena` high and `rst_n` released, `uo_out` shows
`ui_in XOR uio_in` one clock later; after reset it is 0.

## External hardware

An SPI host, such as the RP2350 on the Tiny Tapeout demo board.
