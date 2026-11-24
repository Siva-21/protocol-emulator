# host_link formal testplan

## Part 1 – Scope and references

### Verified

- Block `host_link`: the SPI target that turns one 40-bit host frame into one
  16-bit access on the system bus as master 0. RTL files from
  `src/host_link/host_link.f`: `host_link_sync.sv`, `host_link_ctrl.sv`,
  `host_link_dp.sv`, `host_link.sv` (top module `host_link`).
- Only at the top-level ports of `host_link`: clock/reset, the host SPI pins
  (`spi_sck_i`, `spi_csn_i`, `spi_mosi_i`, `spi_miso_o`) and the system-bus
  master-0 port (`bus_req_o`, `bus_dir_o`, `bus_addr_o`, `bus_wdata_o`,
  `bus_wready_i`, `bus_rready_i`, `bus_rdata_i`).
- Single clock domain `clk` (G-01). The host pins are asynchronous to `clk`, and
  are modelled as inputs sampled on `clk` rising edges.
- Behaviour checked: reset values, frame decoding (address first, one word per
  frame), the bus handshake and its stability, exactly one access per complete
  frame, aborts, ignored bits, MISO behaviour, end-to-end data integrity
  including byte order, and the clock counts of timing figures T3, T4 and T5.

### Not verified

- Gate-level netlist (V9) and X-propagation beyond the RTL reset values.
- Pad, board and host timing on MISO (P6), and the clk/7 limit of V3.
- Metastability, and SCK phases other than whole `clk` cycles. Beyond what the
  SCK-rate assumption (H-1) allows, the analogue SCK phase sweep of V3 is not
  covered.
- Behaviour of the bus targets (SRAM, sub-cores, pin layer, system controller,
  CRC unit, unmapped space), arbitration against the main core (BUS-03), and the
  sub-core programming rule H-4. These are outside the `host_link` ports.

### References

| Document | Version / date | Used for |
|---|---|---|
| `docs/Architecture_spec/Protocol-Emulator-Architecture-1.0.pdf` | 1.0, frozen 27 Oct 2026 | §3 host link, system bus, master priority; §6.1 memory map |
| `docs/Architecture_spec/PE-1.0-Microarchitecture-Requirements.pdf` | derived from Architecture 1.0 (27 Oct 2026) | G-01, G-02, HL-01..HL-09, BUS-01..BUS-06, VER-07 |
| `docs/Implementation_spec/Host_link_implementation_spec.pdf` | frozen 7 Nov 2026 (authoritative) | A-CHG-1, A-CHG-2, §3 frame format and port timing, §5, §6 T1–T5, §7, §8 H-1..H-4, V1–V9, D-HL-1..8 |
| `docs/Implementation_spec/Sysbus_Implementation_Specification.pdf` | v1.0, 15 Nov 2026 | master-0 port timing, bus protocol (BUS-02/BUS-03), read data in W+1 |
| `docs/WORKFLOWS.md` "Formal with sby", `verification/formal/README.md` | repo | sby flow |
| RTL | commit `e81196776fd45246e4e7feda534a935c4fe9a68a` (2026-11-17, "host_link, sys_ctrl, main_ss RTL 0.1v (#4)") | port names only |

## Part 2 – Verification strategy

- **Black box:** every property is written on the `host_link` top-level ports
  only, from the specs (frame format, port timing, timing figures T1–T5, host
  rules, bus protocol, V1–V9); no internal signals, no implementation equations.
- **Assume–guarantee:** properties on inputs are assumptions that model a legal
  SPI host (H-1..H-4) and a legal system bus (BUS-02/BUS-03, waits of 0–8
  clocks); properties on outputs are assertions checked under them.
- **Interface checks:** reset values, the req/dir/addr/wdata handshake and its
  stability, and the T3/T4/T5 clock counts are checked directly on the ports.
- **End-to-end checks:** small helper logic built from the ports (an SPI host
  frame model and a bus scoreboard) checks one access per complete frame,
  aborts, ignored bits, and write/read data integrity including byte order.
- **Edge numbering:** E1, E2, E3, ... are the `clk` rising edges after a pin
  edge, E1 being the first edge that samples the new pin level (Impl spec §6).

## Part 3 – Property table

<table border="1" cellpadding="4" style="border-collapse: collapse;">
<thead>
<tr>
<th>S.no</th><th>Signal Name</th><th>Interface</th><th>IO</th><th>Direction</th><th>Signal Description</th><th>Property ID</th><th>Property</th><th>Helper Logic</th><th>Spec Ref</th><th>Manual Review</th><th>Comments</th>
</tr>
</thead>
<tbody>
<tr>
<td>1</td><td><code>clk</code></td><td>Clock/Reset</td><td>Input</td><td>System to Host link</td>
<td>1 bit. The only clock (50 MHz); every flop samples on its rising edge. SCK is treated as data, never as a clock.</td>
<td>1001</td><td>Assume: clk is the only clock of the block; all state changes on its rising edge.</td><td>None</td><td>G-01, Impl spec §7</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">2</td><td rowspan="2"><code>rst_n</code></td><td rowspan="2">Clock/Reset</td><td rowspan="2">Input</td><td rowspan="2">System to Host link</td>
<td rowspan="2">1 bit, active low. Asserted asynchronously, released synchronously to clk (chip reset synchroniser). Every flop of the block resets to 0; after reset the block is idle and fully functional.</td>
<td>1002</td><td>Assume: rst_n = 0 in the first clock (initial state).</td><td>First-clock flag</td><td>G-02, D-HL-8</td><td></td><td></td>
</tr>
<tr>
<td>1003</td><td>Assume: after the first clock, rst_n may go to 0 at any clock (also in the middle of a frame or a pending access) and returns to 1 only on a clk edge.</td><td>None</td><td>G-02, V7</td><td></td><td></td>
</tr>
<tr>
<td rowspan="3">3</td><td rowspan="3"><code>spi_sck_i</code></td><td rowspan="3">Host</td><td rowspan="3">Input</td><td rowspan="3">Host to Host link</td>
<td rowspan="3">1 bit, SPI clock from the host (ui_in[0]), asynchronous to clk. Mode 0: idle low; MOSI and the host's MISO sample are on the rise, data changes on the fall. Rises while CS_n = 0 are the frame bits 1, 2, ...; a frame has 40 (rises after bit 40 are ignored). Host rate ≤ clk/10.</td>
<td>1101</td><td>Assume: every SCK high level and every SCK low level lasts at least 5 clocks (SCK ≤ clk/10).</td><td>SCK edge timer (level length)</td><td>Impl spec §3 port table, H-1, HL-02</td><td></td><td></td>
</tr>
<tr>
<td>1102</td><td>Assume: spi_sck_i = 0 while rst_n = 0 and while spi_csn_i = 1 (mode 0 idle level, also at reset release).</td><td>None</td><td>H-1, HL-01, Impl spec §7 reset</td><td></td><td></td>
</tr>
<tr>
<td>1103</td><td>Assume: at least 10 clocks (one SCK period at clk/10) from the last SCK rise of a frame to the first SCK rise of the next frame.</td><td>SPI host frame model + SCK edge timer (clocks since last frame rise)</td><td>H-2, V6</td><td></td><td></td>
</tr>
<tr>
<td rowspan="3">4</td><td rowspan="3"><code>spi_csn_i</code></td><td rowspan="3">Host</td><td rowspan="3">Input</td><td rowspan="3">Host to Host link</td>
<td rowspan="3">1 bit, SPI chip select from the host (ui_in[1]), active low, asynchronous to clk. A frame is the time it is 0. High at any time (even for one clock) ends the frame and restarts the next one at bit 1; a write with fewer than 40 bits is dropped, and an access already requested still completes.</td>
<td>1104</td><td>Assume: spi_csn_i changes only while spi_sck_i = 0 (mode 0, CPOL 0).</td><td>None</td><td>H-1, HL-01, Impl spec §3</td><td></td><td></td>
</tr>
<tr>
<td>1105</td><td>Assume: in a frame whose 17th SCK rise samples MOSI = 1 (read), spi_csn_i stays 0 until the 40th SCK rise of that frame (no read abort).</td><td>SPI host frame model</td><td>H-3</td><td></td><td></td>
</tr>
<tr>
<td>1106</td><td>Assume: after rst_n returns to 1, spi_csn_i is 1 for at least one clock before the next SCK rise (the host starts a new frame after a reset).</td><td>SPI host frame model</td><td>HL-07, V7</td><td></td><td></td>
</tr>
<tr>
<td>5</td><td><code>spi_mosi_i</code></td><td>Host</td><td>Input</td><td>Host to Host link</td>
<td>1 bit, SPI data from the host (ui_in[2]), asynchronous to clk. Sampled on SCK rises. Bits 1–16: address, A[7:0] then A[15:8]; bit 17: R/W (1 = read); bits 18–24 ignored; bits 25–40: write data D[7:0] then D[15:8] (ignored on a read). Each byte MSB first.</td>
<td>1107</td><td>Assume: while spi_csn_i = 0, spi_mosi_i does not change in the 5 clocks before an SCK rise or while SCK is high (stable half an SCK period before the rise, mode 0).</td><td>MOSI stability counter + SCK edge timer</td><td>Impl spec §7 CDC, H-1</td><td></td><td></td>
</tr>
<tr>
<td rowspan="4">6</td><td rowspan="4"><code>spi_miso_o</code></td><td rowspan="4">Host</td><td rowspan="4">Output</td><td rowspan="4">Host link to Host</td>
<td rowspan="4">1 bit, SPI data to the host (uo_out[0]), driven at all times. 0 when idle and outside the read-data bytes. In a read frame it carries R[7:0] in bits 25–32 and R[15:8] in bits 33–40, each byte MSB first, where R is the bus read data. Changes 2–3 clocks after a host SCK fall (E3); the host samples on the next SCK rise.</td>
<td>1108</td><td>Assert: spi_miso_o = 0 while rst_n = 0 and in the first clock after reset release.</td><td>None</td><td>D-HL-8, HL-07, HL-08, V9</td><td></td><td></td>
</tr>
<tr>
<td>1109</td><td>Assert: spi_miso_o = 0 outside the read-data window of a read frame: during write frames, frame bits 1–24, after bit 40, while CS_n is high and when idle.</td><td>SPI host frame model + MISO checker (read-data window)</td><td>Impl spec §3, HL-08, V8</td><td></td><td></td>
</tr>
<tr>
<td>1110</td><td>Assert: MISO read-data integrity must be checked (at the SCK rises of bits 25–40, MISO = R[7]..R[0], R[15]..R[8], with R the bus read data of that frame's read, including with 0–8 wait clocks).</td><td>SPI host frame model + bus target scoreboard with a symbolic bit index (one bit of R, any of the 16) + MISO checker</td><td>Impl spec §3, T1, T2, HL-05, D-HL-5, V2, V4</td><td></td><td></td>
</tr>
<tr>
<td>1111</td><td>Assert: MISO bit timing must be checked (inside the read-data window, spi_miso_o changes only at E3 after an SCK fall and holds until E3 after the next fall).</td><td>SCK edge timer + MISO checker</td><td>Impl spec §3 port table, T5</td><td></td><td></td>
</tr>
<tr>
<td>7</td><td><code>bus_wready_i</code></td><td>System bus</td><td>Input</td><td>System bus to Host link</td>
<td>1 bit, active high. Write accepted in this clock when bus_req_o = 1 and bus_dir_o = 1; the write takes effect at the edge ending that clock. Combinational from the interconnect in the same clock (from the address and CRC busy); may be 1 with no request. Low while the target waits (CRC busy, ≤ 8 clocks).</td>
<td>1201</td><td>Assume: while bus_req_o = 1 and bus_dir_o = 1, bus_wready_i is 1 within 8 clocks (at most 8 consecutive clocks with bus_wready_i = 0).</td><td>Wait counter</td><td>Sysbus spec bus protocol, BUS-02, BUS-06, D-HL-4, V4</td><td></td><td></td>
</tr>
<tr>
<td>8</td><td><code>bus_rready_i</code></td><td>System bus</td><td>Input</td><td>System bus to Host link</td>
<td>1 bit, active high. Read accepted in this clock when bus_req_o = 1 and bus_dir_o = 0; the side effect (e.g. FIFO B pop) happens at the edge ending that clock. Combinational from the interconnect in the same clock; may be 1 with no request. Low while the target waits (CRC busy, ≤ 8 clocks).</td>
<td>1202</td><td>Assume: while bus_req_o = 1 and bus_dir_o = 0, bus_rready_i is 1 within 8 clocks (at most 8 consecutive clocks with bus_rready_i = 0).</td><td>Wait counter</td><td>Sysbus spec bus protocol, BUS-02, BUS-06, D-HL-4, V4</td><td></td><td></td>
</tr>
<tr>
<td>9</td><td><code>bus_rdata_i</code></td><td>System bus</td><td>Input</td><td>System bus to Host link</td>
<td>16 bits. Read data, valid only in the clock after the clock that accepted a read (W+1), from target flops; unmapped addresses read 0. Any value in other clocks.</td>
<td>1203</td><td>Assume: bus_rdata_i is free in every clock; its value in the clock after an accepted read is that read's data R.</td><td>Bus target scoreboard (samples R in W+1)</td><td>Sysbus spec bus protocol and port table, BUS-02, Impl spec §3</td><td></td><td></td>
</tr>
<tr>
<td rowspan="8">10</td><td rowspan="8"><code>bus_req_o</code></td><td rowspan="8">System bus</td><td rowspan="8">Output</td><td rowspan="8">Host link to System bus</td>
<td rowspan="8">1 bit, active high, from a flop. Bus request of master 0. Rises at E3 after the 17th SCK rise of a read frame (R/W bit = 1) or after the 40th SCK rise of a write frame. Held, with bus_dir_o, bus_addr_o and bus_wdata_o, until accepted; 0 from the edge that ends the accepting clock. CS_n never cancels it. One access per frame.</td>
<td>1204</td><td>Assert: bus_req_o = 0 while rst_n = 0 and in the first clock after reset release.</td><td>None</td><td>D-HL-8, HL-07, V9</td><td></td><td></td>
</tr>
<tr>
<td>1205</td><td>Assert: if bus_req_o = 1 and the ready of its direction (bus_wready_i when bus_dir_o = 1, bus_rready_i when bus_dir_o = 0) is 0, bus_req_o stays 1 in the next clock, whatever spi_csn_i and spi_sck_i do.</td><td>None</td><td>Impl spec §3 port table, Sysbus spec bus protocol, D-HL-7, HL-04</td><td></td><td></td>
</tr>
<tr>
<td>1206</td><td>Assert: if bus_req_o = 1 and the ready of its direction is 1 (accepted), bus_req_o = 0 in the next clock.</td><td>None</td><td>Impl spec §3 port table, T3, T4, D-HL-7, BUS-05</td><td></td><td></td>
</tr>
<tr>
<td>1207</td><td>Assert: read request timing must be checked (when the 17th SCK rise of a frame samples MOSI = 1, bus_req_o rises at E3 after that rise with bus_dir_o = 0; no read request before bit 17 or when bit 17 = 0).</td><td>SPI host frame model + SCK edge timer</td><td>Impl spec §3, §6 T2, T4, D-HL-5, V5</td><td></td><td></td>
</tr>
<tr>
<td>1208</td><td>Assert: write request timing must be checked (when the 40th SCK rise of a frame with bit 17 = 0 occurs, bus_req_o rises at E3 after that rise with bus_dir_o = 1).</td><td>SPI host frame model + SCK edge timer</td><td>Impl spec §3, §6 T3, V1</td><td></td><td></td>
</tr>
<tr>
<td>1209</td><td>Assert: no bus write for a frame with fewer than 40 SCK rises (CS_n high after any bit 1–39).</td><td>SPI host frame model + bus target scoreboard</td><td>Impl spec §3, HL-06, V5</td><td></td><td></td>
</tr>
<tr>
<td>1210</td><td>Assert: exactly one bus access per complete frame must be checked (one write per frame with ≥ 40 rises and bit 17 = 0, one read per frame with ≥ 17 rises and bit 17 = 1, no other access).</td><td>SPI host frame model + bus target scoreboard (access counter per frame)</td><td>A-CHG-2, HL-04, HL-05, BUS-05, V1, V2, V5</td><td></td><td></td>
</tr>
<tr>
<td>1211</td><td>Assert: SCK rises after bit 40 of a frame cause no bus request.</td><td>SPI host frame model + bus target scoreboard</td><td>Impl spec §3, V7</td><td></td><td></td>
</tr>
<tr>
<td rowspan="3">11</td><td rowspan="3"><code>bus_dir_o</code></td><td rowspan="3">System bus</td><td rowspan="3">Output</td><td rowspan="3">Host link to System bus</td>
<td rowspan="3">1 bit. Access direction: 1 = write, 0 = read. Set from the R/W bit (frame bit 17) of the current frame; CMD bits 18–24 are ignored. Meaningful while bus_req_o = 1 and stable for that whole time. Reset value 1 (R/W flop reset to 0).</td>
<td>1212</td><td>Assert: bus_dir_o = 1 while rst_n = 0 and in the first clock after reset release.</td><td>None</td><td>Impl spec §3 port table, D-HL-8</td><td></td><td></td>
</tr>
<tr>
<td>1213</td><td>Assert: if bus_req_o = 1 and not accepted, bus_dir_o is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 port table, Sysbus spec bus protocol</td><td></td><td></td>
</tr>
<tr>
<td>1214</td><td>Assert: access direction integrity must be checked (for every access, bus_dir_o = NOT frame bit 17 of its frame, whatever MOSI is in bits 18–24).</td><td>SPI host frame model + bus target scoreboard</td><td>Impl spec §3, V7</td><td></td><td></td>
</tr>
<tr>
<td rowspan="3">12</td><td rowspan="3"><code>bus_addr_o</code></td><td rowspan="3">System bus</td><td rowspan="3">Output</td><td rowspan="3">Host link to System bus</td>
<td rowspan="3">16 bits, 16-bit word address A[15:0] of the frame (bits 1–8 = A[7:0], bits 9–16 = A[15:8], each MSB first; address before command, A-CHG-1). Wiring from flops. Meaningful while bus_req_o = 1 and stable for that whole time. Reset value 0. Any value reaches any target (unmapped included).</td>
<td>1215</td><td>Assert: bus_addr_o = 0 while rst_n = 0 and in the first clock after reset release.</td><td>None</td><td>Impl spec §3 port table, D-HL-8</td><td></td><td></td>
</tr>
<tr>
<td>1216</td><td>Assert: if bus_req_o = 1 and not accepted, bus_addr_o is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 port table, Sysbus spec bus protocol, H-2</td><td></td><td></td>
</tr>
<tr>
<td>1217</td><td>Assert: write and read address integrity must be checked (in the accepting clock, bus_addr_o = {frame bits 9–16, frame bits 1–8}, each byte MSB first, for the frame that issued the access; a frame restarted by CS_n high is decoded from its own bit 1).</td><td>SPI host frame model + bus target scoreboard</td><td>A-CHG-1, Impl spec §3, T1, V1, V2, V7</td><td></td><td></td>
</tr>
<tr>
<td rowspan="3">13</td><td rowspan="3"><code>bus_wdata_o</code></td><td rowspan="3">System bus</td><td rowspan="3">Output</td><td rowspan="3">Host link to System bus</td>
<td rowspan="3">16 bits, write data D[15:0] of a write frame (bits 25–32 = D[7:0], bits 33–40 = D[15:8], each MSB first). Wiring from flops. Meaningful while bus_req_o = 1 and bus_dir_o = 1, and stable for that whole time. Reset value 0.</td>
<td>1218</td><td>Assert: bus_wdata_o = 0 while rst_n = 0 and in the first clock after reset release.</td><td>None</td><td>Impl spec §3 port table, D-HL-8</td><td></td><td></td>
</tr>
<tr>
<td>1219</td><td>Assert: if bus_req_o = 1, bus_dir_o = 1 and not accepted, bus_wdata_o is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 port table, Sysbus spec bus protocol, H-2</td><td></td><td></td>
</tr>
<tr>
<td>1220</td><td>Assert: write data integrity must be checked (in the accepting clock of a write, bus_wdata_o = {frame bits 33–40, frame bits 25–32}, each byte MSB first).</td><td>SPI host frame model + bus target scoreboard</td><td>Impl spec §3, T1, A-CHG-2, V1</td><td></td><td></td>
</tr>
</tbody>
</table>
