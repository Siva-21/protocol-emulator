# sysbus formal testplan

## Part 1 – Scope and references

### Verified

- Block `sysbus`: the system bus with two masters (host link = master 0, main
  core = master 1), the host-only target port to main_ss (SRAM 0x0000–0x01FF,
  CRC unit 0x1C10–0x1C1F), and the shared bus targets (called the chip bus in
  the Impl spec) with one-hot selects: sys_ctrl, sub-cores 0–3 and the pin
  layer; unmapped addresses are accepted and read 0. RTL file from
  `src/sysbus/sysbus.f`: `sysbus.v` (top module `sysbus`).
- Only at the top-level ports of `sysbus`: clock/reset, the host master port
  (`h_*`), the core master port (`m_*`), the main_ss target port (`t_*`) and the
  bus-target ports (`sys_req_o`, `sc_req_o`, `pl_req_o`, `c_dir_o`,
  `c_addr_o`, `c_wdata_o`, `sys_rdata_i`, `sc_rdata_i`, `pl_rdata_i`).
- Single clock domain `clk` (G-01).
- Behaviour checked: the bus handshake on every port and its stability, the
  address map for both masters (all 16 address bits, unmapped space included),
  host-first arbitration of the bus targets, forwarding of the CRC wait to the host,
  independence of the ready outputs, one target access per accepted master access,
  and read data returned to the right master in the clock after the read (W+1),
  including the sub-core slice order of `sc_rdata_i`.

### Not verified

- Gate-level netlist and X on `m_addr_i` and the read-select state in clocks where
  read data is unused (V6).
- Timing paths, the `c_addr` / `c_wdata` fan-out and floorplan effects (§7, §8.5),
  and area.
- Behaviour of the targets (register writes, FIFO B pop and other read side
  effects, CRC busy length), the main core's local SRAM/CRC arbitration inside
  main_ss, and the sideband wiring (D-BUS-1). These are outside the `sysbus` ports.
- The full-chip system run with every block (V5).

### References

| Document | Version / date | Used for |
|---|---|---|
| `docs/Implementation_spec/Sysbus_Implementation_Specification.pdf` ("Impl spec" below) | v1.0, 15 Nov 2026 | §1 D-BUS-1..4; §2 micro-architecture (text); §3 interface, port timing table, bus protocol, address map, requirements on neighbours; §5 chip-bus ownership table; §6 T1–T3; §7 clocking and reset; §8.1 B-1..B-3; §8.2 V1–V6; §8.4 D-BUS-5..9 |
| `docs/Architecture_spec/PE-1.0-Microarchitecture-Requirements.pdf` | derived from Architecture 1.0 (27 Oct 2026) | G-01, G-02, BUS-01..BUS-06, HL-04, HL-05, CRC-03, CRC-04 |
| `docs/Architecture_spec/Protocol-Emulator-Architecture-1.0.pdf` | 1.0, frozen 27 Oct 2026 | §3 system bus, §6.1 memory map, §6.2 sub-core window |
| `docs/Implementation_spec/Main_Subsystem_implementation_specification.pdf` ("Main_ss spec") | v1.1, 15 Nov 2026 | §3.1 bus protocol, §3.2 target port, §3.3 master port, §3.4, §8.4 (CRC busy time), D-MC-8, A-CHG-8 |
| `docs/Implementation_spec/Host_link_implementation_spec.pdf` ("Host_link spec") | frozen 7 Nov 2026 | §3 bus port (master 0) |
| `docs/Implementation_spec/System_control_implementation_specification_v1.2.pdf` ("Sys_ctrl spec") | v1.2, 10 Nov 2026 | §2.1 bus target port, AS-1 |
| `docs/Implementation_spec/Subcore_Implementation_Specification.pdf` ("Subcore spec") | v1.0, 15 Nov 2026 | §3 bus window port |
| `docs/Implementation_spec/Pin_layer_Implementation_Specification.pdf` ("Pin_layer spec") | v1.0, 15 Nov 2026 | §3 bus window port |
| `docs/Integration_spec/Top_level_Integration_Specification_v1.pdf` ("Integration spec") | v1.0, 15 Nov 2026 | `u_bus` connections, `sc_rdata_i` order |
| `verification/formal/fv_host_link/testplan/host_link_fv_testplan.md` | branch `verif/host-link` @ `667d206` | system-bus interface properties mirrored here |
| `docs/WORKFLOWS.md` "Formal with sby", `verification/formal/README.md` | repo | sby flow |
| RTL | commit `e81196776fd45246e4e7feda534a935c4fe9a68a` (2026-11-17, "host_link, sys_ctrl, main_ss RTL 0.1v (#4)") | port names only |

## Part 2 – Verification strategy

- **Black box:** every property is written on the `sysbus` top-level ports only,
  from the specs (port table, bus protocol, address map, ownership table, timing
  figures, rules B-1..B-3, V1–V6); no internal signals, no implementation equations.
- **Assume–guarantee:** properties on inputs are assumptions that model legal
  masters (host link, main core) and legal targets (main_ss target port, bus
  targets); properties on outputs are assertions checked under them.
- **Shared interface:** the host master port is the system-bus port of
  `fv_host_link`; its interface properties are mirrored here with the roles
  swapped (its assumptions are assertions here and vice versa).
- **Terms:** W is the clock in which an access is accepted (req = 1 and the ready
  of its direction = 1); read data is checked in W+1. The *main_ss range* is
  0x0000–0x01FF and 0x1C10–0x1C1F; every other address is a *bus-target address*
  (unmapped included). The *bus-target owner* of a clock is the host if
  h_req_i = 1 with a bus-target address, otherwise the core if m_req_i = 1,
  otherwise none.

## Part 3 – Property table

<table border="1" cellpadding="4" style="border-collapse: collapse;">
<thead>
<tr>
<th>S.no</th><th>Signal Name</th><th>Interface</th><th>IO</th><th>Direction</th><th>Signal Description</th><th>Property ID</th><th>Property</th><th>Helper Logic</th><th>Spec Ref</th><th>Manual Review</th><th>Comments</th>
</tr>
</thead>
<tbody>
<tr>
<td>1</td><td><code>clk</code></td><td>Clock/Reset</td><td>Input</td><td>System to Sysbus</td>
<td>1 bit. The only clock (50 MHz); every flop samples on its rising edge. No gated clocks, no latches.</td>
<td>2001</td><td>Assume: clk is the only clock of the block; all state changes on its rising edge.</td><td>None</td><td>G-01, Impl spec §7</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">2</td><td rowspan="2"><code>rst_n</code></td><td rowspan="2">Clock/Reset</td><td rowspan="2">Input</td><td rowspan="2">System to Sysbus</td>
<td rowspan="2">1 bit, active low. Synchronised at chip level: asserted asynchronously, released synchronously to clk. The read-select flops reset to 0 (class 0, chip path); no read can be pending at reset.</td>
<td>2002</td><td>Assume: rst_n = 0 in the first clock (initial state).</td><td>First-clock flag</td><td>G-02, Impl spec §3, §7</td><td></td><td></td>
</tr>
<tr>
<td>2003</td><td>Assume: after the first clock, rst_n may go to 0 at any clock (also while an access is pending or waiting) and returns to 1 only on a clk edge.</td><td>None</td><td>G-02, Impl spec §7</td><td></td><td></td>
</tr>
<tr>
<td rowspan="3">3</td><td rowspan="3"><code>h_req_i</code></td><td rowspan="3">Host link</td><td rowspan="3">Input</td><td rowspan="3">Host link to Sysbus</td>
<td rowspan="3">1 bit, active high, from a host-link flop. Bus request of master 0. Held, with h_dir_i, h_addr_i and h_wdata_i, until accepted. The host wins the bus targets over the core in every clock.</td>
<td>2101</td><td>Assume: h_req_i = 0 while rst_n = 0 and in the first clock after reset release.</td><td>None</td><td>Host_link spec §3, HL-07</td><td></td><td>Mirrors 1204 of fv_host_link</td>
</tr>
<tr>
<td>2102</td><td>Assume: if h_req_i = 1 and the ready of its direction (h_wready_o when h_dir_i = 1, h_rready_o when h_dir_i = 0) is 0, h_req_i stays 1 in the next clock.</td><td>None</td><td>Impl spec §3 port table and bus protocol, HL-04</td><td></td><td>Mirrors 1205 of fv_host_link</td>
</tr>
<tr>
<td>2103</td><td>Assume: if h_req_i = 1 and the ready of its direction is 1 (accepted), h_req_i = 0 in the next clock.</td><td>None</td><td>Host_link spec §3, BUS-05</td><td></td><td>Mirrors 1206 of fv_host_link</td>
</tr>
<tr>
<td rowspan="2">4</td><td rowspan="2"><code>h_dir_i</code></td><td rowspan="2">Host link</td><td rowspan="2">Input</td><td rowspan="2">Host link to Sysbus</td>
<td rowspan="2">1 bit. Access direction of master 0: 1 = write, 0 = read. Meaningful while h_req_i = 1 and stable for that whole time.</td>
<td>2104</td><td>Assume: h_dir_i = 1 while rst_n = 0 and in the first clock after reset release.</td><td>None</td><td>Host_link spec §3</td><td></td><td>Mirrors 1212 of fv_host_link</td>
</tr>
<tr>
<td>2105</td><td>Assume: if h_req_i = 1 and not accepted, h_dir_i is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 bus protocol, requirements on neighbours</td><td></td><td>Mirrors 1213 of fv_host_link</td>
</tr>
<tr>
<td rowspan="2">5</td><td rowspan="2"><code>h_addr_i</code></td><td rowspan="2">Host link</td><td rowspan="2">Input</td><td rowspan="2">Host link to Sysbus</td>
<td rowspan="2">16 bits, word address of master 0. Any value: the main_ss range goes to the main_ss target port, every other address to the bus targets (unmapped included). Meaningful while h_req_i = 1 and stable for that whole time.</td>
<td>2106</td><td>Assume: h_addr_i = 0 while rst_n = 0 and in the first clock after reset release.</td><td>None</td><td>Host_link spec §3</td><td></td><td>Mirrors 1215 of fv_host_link</td>
</tr>
<tr>
<td>2107</td><td>Assume: if h_req_i = 1 and not accepted, h_addr_i is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 bus protocol, requirements on neighbours</td><td></td><td>Mirrors 1216 of fv_host_link</td>
</tr>
<tr>
<td rowspan="2">6</td><td rowspan="2"><code>h_wdata_i</code></td><td rowspan="2">Host link</td><td rowspan="2">Input</td><td rowspan="2">Host link to Sysbus</td>
<td rowspan="2">16 bits, write data of master 0. Meaningful while h_req_i = 1 and h_dir_i = 1, and stable for that whole time.</td>
<td>2108</td><td>Assume: h_wdata_i = 0 while rst_n = 0 and in the first clock after reset release.</td><td>None</td><td>Host_link spec §3</td><td></td><td>Mirrors 1218 of fv_host_link</td>
</tr>
<tr>
<td>2109</td><td>Assume: if h_req_i = 1, h_dir_i = 1 and not accepted, h_wdata_i is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 bus protocol, requirements on neighbours</td><td></td><td>Mirrors 1219 of fv_host_link</td>
</tr>
<tr>
<td rowspan="4">7</td><td rowspan="4"><code>h_wready_o</code></td><td rowspan="4">Host link</td><td rowspan="4">Output</td><td rowspan="4">Sysbus to Host link</td>
<td rowspan="4">1 bit, active high. Write of master 0 accepted in this clock when h_req_i = 1 and h_dir_i = 1. Combinational from h_addr_i and t_wready_i; independent of h_wdata_i and the m_* signals. 1 at once for bus-target addresses (unmapped included); forwards the main_ss target's wait (CRC busy) for the main_ss range.</td>
<td>2110</td><td>Assert: while h_req_i = 1 and h_dir_i = 1, h_wready_o is 1 within 10 clocks (CRC busy: 8 bits + 2 stuff bits; at most 10 consecutive clocks with h_wready_o = 0).</td><td>Wait counter</td><td>Impl spec bus protocol, BUS-02, BUS-06, B-3, Main_ss spec §8.4</td><td></td><td>Mirrors 1201 of fv_host_link</td>
</tr>
<tr>
<td>2111</td><td>Assert: a host write to a bus-target address (h_req_i = 1, h_dir_i = 1, h_addr_i outside the main_ss range) has h_wready_o = 1 (accepted in its first clock).</td><td>Address range decode (spec map)</td><td>Impl spec §2, §3 address map, §5, D-BUS-7, B-1</td><td></td><td></td>
</tr>
<tr>
<td>2501</td><td>Assert: while h_req_i = 1, h_dir_i = 1 and h_addr_i is in the main_ss range, h_wready_o = t_wready_i (the main_ss target's wait is forwarded).</td><td>Address range decode (spec map)</td><td>Impl spec §2, §3 port table, T2, B-3, CRC-04</td><td></td><td></td>
</tr>
<tr>
<td>2502</td><td>Assert: h_wready_o does not change when only h_wdata_i or the m_* inputs change.</td><td>Two-copy check (self-composition)</td><td>Impl spec §3 port table, V3</td><td></td><td></td>
</tr>
<tr>
<td rowspan="4">8</td><td rowspan="4"><code>h_rready_o</code></td><td rowspan="4">Host link</td><td rowspan="4">Output</td><td rowspan="4">Sysbus to Host link</td>
<td rowspan="4">1 bit, active high. Read of master 0 accepted in this clock when h_req_i = 1 and h_dir_i = 0; the target's side effect happens at the edge ending that clock. Combinational from h_addr_i and t_rready_i; independent of h_wdata_i and the m_* signals. 1 at once for bus-target addresses (unmapped included); forwards the main_ss target's wait (CRC busy) for the main_ss range.</td>
<td>2112</td><td>Assert: while h_req_i = 1 and h_dir_i = 0, h_rready_o is 1 within 10 clocks (CRC busy: 8 bits + 2 stuff bits; at most 10 consecutive clocks with h_rready_o = 0).</td><td>Wait counter</td><td>Impl spec bus protocol, BUS-02, BUS-06, B-3, Main_ss spec §8.4</td><td></td><td>Mirrors 1202 of fv_host_link</td>
</tr>
<tr>
<td>2113</td><td>Assert: a host read of a bus-target address (h_req_i = 1, h_dir_i = 0, h_addr_i outside the main_ss range) has h_rready_o = 1 (accepted in its first clock).</td><td>Address range decode (spec map)</td><td>Impl spec §2, §3 address map, §5, T3, D-BUS-7, B-1</td><td></td><td></td>
</tr>
<tr>
<td>2503</td><td>Assert: while h_req_i = 1, h_dir_i = 0 and h_addr_i is in the main_ss range, h_rready_o = t_rready_i (the main_ss target's wait is forwarded).</td><td>Address range decode (spec map)</td><td>Impl spec §2, §3 port table, T2, B-3, CRC-04</td><td></td><td></td>
</tr>
<tr>
<td>2504</td><td>Assert: h_rready_o does not change when only h_wdata_i or the m_* inputs change.</td><td>Two-copy check (self-composition)</td><td>Impl spec §3 port table, V3</td><td></td><td></td>
</tr>
<tr>
<td>9</td><td><code>h_rdata_o</code></td><td>Host link</td><td>Output</td><td>Sysbus to Host link</td>
<td>16 bits. Read data of master 0, valid only in the clock after the clock that accepted its read (W+1): t_rdata_i for the main_ss range, the addressed bus target's read data for bus-target addresses, 0 for unmapped addresses. Any value in other clocks.</td>
<td>2114</td><td>Assert: in the clock after an accepted host read, h_rdata_o = that read's data R.</td><td>Bus target scoreboard (R = the addressed target's read data in W+1: t_rdata_i for the main_ss range, sys_rdata_i, sc_rdata_i[16n+15:16n] for sub-core n, pl_rdata_i; 0 for an unmapped address)</td><td>Impl spec §3 port table, bus protocol, §6 T2, T3, BUS-02, D-BUS-4, D-BUS-7, B-1, V2</td><td></td><td>Mirrors 1203 of fv_host_link</td>
</tr>
<tr>
<td>10</td><td><code>m_req_i</code></td><td>Main_ss</td><td>Input</td><td>main_ss to Sysbus</td>
<td>1 bit, active high. Bus request of master 1 (main core), combinational from the core, late in the clock. 1 in every EXEC clock of a load or store to the bus targets; when not accepted the core stalls and repeats the request in the next clock.</td>
<td>–</td><td>None (free input).</td><td>None</td><td></td><td></td><td></td>
</tr>
<tr>
<td>11</td><td><code>m_dir_i</code></td><td>Main_ss</td><td>Input</td><td>main_ss to Sysbus</td>
<td>1 bit. Access direction of master 1: 1 = write, 0 = read. Meaningful while m_req_i = 1.</td>
<td>2201</td><td>Assume: if m_req_i = 1 and not accepted, m_dir_i is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 bus protocol, Main_ss spec §3.1</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">12</td><td rowspan="2"><code>m_addr_i</code></td><td rowspan="2">Main_ss</td><td rowspan="2">Input</td><td rowspan="2">main_ss to Sysbus</td>
<td rowspan="2">16 bits, word address of master 1. Only bus-target addresses: the core reaches SRAM and the CRC unit locally inside main_ss. Meaningful while m_req_i = 1.</td>
<td>2202</td><td>Assume: if m_req_i = 1 and not accepted, m_addr_i is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 bus protocol, Main_ss spec §3.1</td><td></td><td></td>
</tr>
<tr>
<td>2203</td><td>Assume: while m_req_i = 1, m_addr_i is outside the main_ss range (0x0000–0x01FF and 0x1C10–0x1C1F).</td><td>Address range decode (spec map)</td><td>Impl spec §2, §3 requirements on neighbours, D-MC-8</td><td></td><td></td>
</tr>
<tr>
<td>13</td><td><code>m_wdata_i</code></td><td>Main_ss</td><td>Input</td><td>main_ss to Sysbus</td>
<td>16 bits, write data of master 1. Meaningful while m_req_i = 1 and m_dir_i = 1.</td>
<td>2204</td><td>Assume: if m_req_i = 1, m_dir_i = 1 and not accepted, m_wdata_i is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 bus protocol, Main_ss spec §3.1</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">14</td><td rowspan="2"><code>m_wready_o</code></td><td rowspan="2">Main_ss</td><td rowspan="2">Output</td><td rowspan="2">Sysbus to main_ss</td>
<td rowspan="2">1 bit, active high. Write of master 1 accepted in this clock when m_req_i = 1 and m_dir_i = 1. From h_req_i and h_addr_i only; never depends on m_req_i. 0 exactly in clocks where the host's own access goes to the bus targets (host first); 1 while the host is idle or uses the main_ss range.</td>
<td>2505</td><td>Assert: m_wready_o = 0 exactly in clocks where h_req_i = 1 and h_addr_i is a bus-target address; m_wready_o = 1 in every other clock.</td><td>Address range decode (spec map)</td><td>Impl spec §2, §3 port table, §5, T1, T2, BUS-03, D-BUS-2, A-CHG-8, Main_ss spec §3.3, V3</td><td></td><td></td>
</tr>
<tr>
<td>2506</td><td>Assert: m_wready_o is never 0 in two consecutive clocks (the core is held at most one clock per host bus-target access).</td><td>None</td><td>Impl spec §5, T1, B-2, D-BUS-2</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">15</td><td rowspan="2"><code>m_rready_o</code></td><td rowspan="2">Main_ss</td><td rowspan="2">Output</td><td rowspan="2">Sysbus to main_ss</td>
<td rowspan="2">1 bit, active high. Read of master 1 accepted in this clock when m_req_i = 1 and m_dir_i = 0. From h_req_i and h_addr_i only; never depends on m_req_i. 0 exactly in clocks where the host's own access goes to the bus targets (host first); 1 while the host is idle or uses the main_ss range.</td>
<td>2507</td><td>Assert: m_rready_o = 0 exactly in clocks where h_req_i = 1 and h_addr_i is a bus-target address; m_rready_o = 1 in every other clock.</td><td>Address range decode (spec map)</td><td>Impl spec §2, §3 port table, §5, T1, T2, BUS-03, D-BUS-2, A-CHG-8, Main_ss spec §3.3, V3</td><td></td><td></td>
</tr>
<tr>
<td>2508</td><td>Assert: m_rready_o is never 0 in two consecutive clocks (the core is held at most one clock per host bus-target access).</td><td>None</td><td>Impl spec §5, B-2, D-BUS-2</td><td></td><td></td>
</tr>
<tr>
<td>16</td><td><code>m_rdata_o</code></td><td>Main_ss</td><td>Output</td><td>Sysbus to main_ss</td>
<td>16 bits. Read data of master 1, valid only in the clock after the clock that accepted its read (W+1): the addressed bus target's read data, 0 for unmapped addresses. Any value in other clocks.</td>
<td>2509</td><td>Assert: core read data integrity must be checked (in the clock after an accepted core read, m_rdata_o = the addressed bus target's read data: sys_rdata_i, sc_rdata_i[16n+15:16n] for sub-core n, pl_rdata_i; 0 for an unmapped address; also when a host read of the main_ss range is accepted in the same clock).</td><td>Bus target scoreboard (samples the addressed target's read data in W+1)</td><td>Impl spec §3 port table, bus protocol, §6 T1, T2, BUS-02, A-CHG-8, D-BUS-7, B-1, V2</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">17</td><td rowspan="2"><code>t_req_o</code></td><td rowspan="2">Main_ss</td><td rowspan="2">Output</td><td rowspan="2">Sysbus to main_ss</td>
<td rowspan="2">1 bit, active high. Request to the main_ss target port (SRAM and CRC unit); host only, one select for both ranges. Held, with t_dir_o, t_addr_o and t_wdata_o, while the target waits.</td>
<td>2301</td><td>Assert: if t_req_o = 1 and the ready of its direction (t_wready_i when t_dir_o = 1, t_rready_i when t_dir_o = 0) is 0, t_req_o stays 1 in the next clock.</td><td>None</td><td>Impl spec §3 bus protocol, Main_ss spec §3.1</td><td></td><td></td>
</tr>
<tr>
<td>2510</td><td>Assert: t_req_o = 1 exactly in clocks where h_req_i = 1 and h_addr_i is in the main_ss range (never for a core access).</td><td>Address range decode (spec map)</td><td>Impl spec §2, §3 address map, D-BUS-5, D-MC-8, Main_ss spec §3.2, V1</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">18</td><td rowspan="2"><code>t_dir_o</code></td><td rowspan="2">Main_ss</td><td rowspan="2">Output</td><td rowspan="2">Sysbus to main_ss</td>
<td rowspan="2">1 bit. Direction of the host access on the main_ss target port: 1 = write, 0 = read. Wiring from the host link. Meaningful while t_req_o = 1.</td>
<td>2302</td><td>Assert: if t_req_o = 1 and not accepted, t_dir_o is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 bus protocol, Main_ss spec §3.1</td><td></td><td></td>
</tr>
<tr>
<td>2511</td><td>Assert: while t_req_o = 1, t_dir_o = h_dir_i.</td><td>None</td><td>Impl spec §2, §3 port table, V2</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">19</td><td rowspan="2"><code>t_addr_o</code></td><td rowspan="2">Main_ss</td><td rowspan="2">Output</td><td rowspan="2">Sysbus to main_ss</td>
<td rowspan="2">16 bits. Address of the host access on the main_ss target port (main_ss uses bit 12 to pick SRAM or CRC, bits [8:0] or [3:0] as offset). Wiring from the host link. Meaningful while t_req_o = 1.</td>
<td>2303</td><td>Assert: if t_req_o = 1 and not accepted, t_addr_o is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 bus protocol, Main_ss spec §3.1</td><td></td><td></td>
</tr>
<tr>
<td>2512</td><td>Assert: while t_req_o = 1, t_addr_o = h_addr_i (all 16 bits).</td><td>None</td><td>Impl spec §2, §3 port table, Main_ss spec §3.2, V2</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">20</td><td rowspan="2"><code>t_wdata_o</code></td><td rowspan="2">Main_ss</td><td rowspan="2">Output</td><td rowspan="2">Sysbus to main_ss</td>
<td rowspan="2">16 bits. Write data of the host access on the main_ss target port. Wiring from the host link. Meaningful while t_req_o = 1 and t_dir_o = 1.</td>
<td>2304</td><td>Assert: if t_req_o = 1, t_dir_o = 1 and not accepted, t_wdata_o is unchanged in the next clock.</td><td>None</td><td>Impl spec §3 bus protocol, Main_ss spec §3.1</td><td></td><td></td>
</tr>
<tr>
<td>2513</td><td>Assert: while t_req_o = 1 and t_dir_o = 1, t_wdata_o = h_wdata_i.</td><td>None</td><td>Impl spec §2, §3 port table, V2</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">21</td><td rowspan="2"><code>t_wready_i</code></td><td rowspan="2">Main_ss</td><td rowspan="2">Input</td><td rowspan="2">main_ss to Sysbus</td>
<td rowspan="2">1 bit, active high. Write accepted by the main_ss target port. From t_addr and CRC busy: 0 for a CRC DATA write while the unit is busy, until it is idle (up to 8 clocks plus stuff bits). Does not depend on t_req_o.</td>
<td>2305</td><td>Assume: t_wready_i does not depend on t_req_o in the same clock.</td><td>Two-copy check (self-composition)</td><td>Impl spec §3 port table, requirements on neighbours, Main_ss spec §3.2</td><td></td><td></td>
</tr>
<tr>
<td>2308</td><td>Assume: while t_req_o = 1 and t_dir_o = 1, t_wready_i is 1 within 10 clocks (CRC busy: 8 bits + 2 stuff bits; at most 10 consecutive clocks with t_wready_i = 0).</td><td>Wait counter</td><td>Impl spec §3 port table, B-3, BUS-06, CRC-03, CRC-04, Main_ss spec §3.2, §8.4</td><td></td><td>Needed for 2110. Check as an assertion on the main_ss target side.</td>
</tr>
<tr>
<td rowspan="2">22</td><td rowspan="2"><code>t_rready_i</code></td><td rowspan="2">Main_ss</td><td rowspan="2">Input</td><td rowspan="2">main_ss to Sysbus</td>
<td rowspan="2">1 bit, active high. Read accepted by the main_ss target port. From t_addr and CRC busy: 0 for a CRC VAL read while the unit is busy, until it is idle (up to 8 clocks plus stuff bits). Does not depend on t_req_o.</td>
<td>2306</td><td>Assume: t_rready_i does not depend on t_req_o in the same clock.</td><td>Two-copy check (self-composition)</td><td>Impl spec §3 port table, requirements on neighbours, Main_ss spec §3.2</td><td></td><td></td>
</tr>
<tr>
<td>2309</td><td>Assume: while t_req_o = 1 and t_dir_o = 0, t_rready_i is 1 within 10 clocks (CRC busy: 8 bits + 2 stuff bits; at most 10 consecutive clocks with t_rready_i = 0).</td><td>Wait counter</td><td>Impl spec §3 port table, B-3, BUS-06, CRC-03, CRC-04, Main_ss spec §3.2, §8.4</td><td></td><td>Needed for 2112. Check as an assertion on the main_ss target side.</td>
</tr>
<tr>
<td>23</td><td><code>t_rdata_i</code></td><td>Main_ss</td><td>Input</td><td>main_ss to Sysbus</td>
<td>16 bits. Read data of the main_ss target port (SRAM or CRC register), valid only in the clock after the clock that accepted the read (W+1). Any value in other clocks.</td>
<td>2307</td><td>Assume: t_rdata_i is free in every clock; its value in the clock after an accepted read on the main_ss target port is that read's data.</td><td>Bus target scoreboard (samples t_rdata_i in W+1)</td><td>Impl spec §3 port table, bus protocol, Main_ss spec §3.1, §3.2, BUS-02</td><td></td><td></td>
</tr>
<tr>
<td>24</td><td><code>sys_req_o</code></td><td>Sys_ctrl</td><td>Output</td><td>Sysbus to sys_ctrl</td>
<td>1 bit, active high. One-hot select of sys_ctrl (0x1C00–0x1C0F). The target accepts in every clock with req = 1 (ready tied 1) and acts at the edge ending it.</td>
<td>2514</td><td>Assert: sys_req_o = 1 exactly in clocks where the bus-target owner's address is in 0x1C00–0x1C0F.</td><td>Bus-target owner + address range decode (spec map)</td><td>Impl spec §2, §3 address map, §5, T2, BUS-03, BUS-04, D-BUS-6, Sys_ctrl spec §2.1 AS-1, V1, V2</td><td></td><td></td>
</tr>
<tr>
<td rowspan="2">25</td><td rowspan="2"><code>sc_req_o</code></td><td rowspan="2">Sub-cores</td><td rowspan="2">Output</td><td rowspan="2">Sysbus to sub-cores</td>
<td rowspan="2">4 bits, active high. One-hot select of sub-core n = 0..3 (bit n, window 0x1000 + 0x80·n, 128 words). Each sub-core accepts in every clock with its req = 1 (ready tied 1). At most one of sys_req_o, sc_req_o[3:0] and pl_req_o is 1 in a clock.</td>
<td>2401</td><td>Assert: at most one of sys_req_o, sc_req_o[0], sc_req_o[1], sc_req_o[2], sc_req_o[3] and pl_req_o is 1 in a clock.</td><td>None</td><td>Impl spec §3 port table, §4.2 text, AS-1</td><td></td><td></td>
</tr>
<tr>
<td>2515</td><td>Assert: sc_req_o[n] = 1 exactly in clocks where the bus-target owner's address is in 0x1000 + 0x80·n to 0x107F + 0x80·n (n = 0..3).</td><td>Bus-target owner + address range decode (spec map)</td><td>Impl spec §2, §3 address map, §5, T1, T3, BUS-03, BUS-04, BUS-05, D-BUS-6, Subcore spec §3, V1, V2</td><td></td><td></td>
</tr>
<tr>
<td>26</td><td><code>pl_req_o</code></td><td>Pin layer</td><td>Output</td><td>Sysbus to pin layer</td>
<td>1 bit, active high. One-hot select of the pin layer (0x1800–0x181F). The target accepts in every clock with req = 1 (ready tied 1).</td>
<td>2516</td><td>Assert: pl_req_o = 1 exactly in clocks where the bus-target owner's address is in 0x1800–0x181F.</td><td>Bus-target owner + address range decode (spec map)</td><td>Impl spec §2, §3 address map, §5, T1, BUS-03, BUS-04, D-BUS-6, Pin_layer spec §3, V1, V2</td><td></td><td></td>
</tr>
<tr>
<td>27</td><td><code>c_dir_o</code></td><td>Sys_ctrl, Sub-cores, Pin layer</td><td>Output</td><td>Sysbus to sys_ctrl, sub-cores and pin layer</td>
<td>1 bit. Direction of the bus-target access (1 = write), broadcast to all bus targets. Meaningful only while a target's req is 1.</td>
<td>2517</td><td>Assert: while sys_req_o, any bit of sc_req_o or pl_req_o is 1, c_dir_o = the bus-target owner's dir (h_dir_i if the host owns the bus targets, else m_dir_i).</td><td>Bus-target owner</td><td>Impl spec §2, §3 port table, §5, D-BUS-9, V2</td><td></td><td></td>
</tr>
<tr>
<td>28</td><td><code>c_addr_o</code></td><td>Sys_ctrl, Sub-cores, Pin layer</td><td>Output</td><td>Sysbus to sys_ctrl, sub-cores and pin layer</td>
<td>16 bits. Full address of the bus-target access, broadcast; targets keep their low bits (sys_ctrl [3:0], sub-cores [6:0], pin layer [4:0]). Meaningful only while a target's req is 1.</td>
<td>2518</td><td>Assert: while sys_req_o, any bit of sc_req_o or pl_req_o is 1, c_addr_o = the bus-target owner's address, all 16 bits (h_addr_i if the host owns the bus targets, else m_addr_i).</td><td>Bus-target owner</td><td>Impl spec §2, §3 port table, §5, D-BUS-9, V1, V2</td><td></td><td></td>
</tr>
<tr>
<td>29</td><td><code>c_wdata_o</code></td><td>Sys_ctrl, Sub-cores, Pin layer</td><td>Output</td><td>Sysbus to sys_ctrl, sub-cores and pin layer</td>
<td>16 bits. Write data of the bus-target access, broadcast. Meaningful only while a target's req is 1 and c_dir_o = 1.</td>
<td>2519</td><td>Assert: while sys_req_o, any bit of sc_req_o or pl_req_o is 1 and c_dir_o = 1, c_wdata_o = the bus-target owner's write data (h_wdata_i if the host owns the bus targets, else m_wdata_i).</td><td>Bus-target owner</td><td>Impl spec §2, §3 port table, §5, T1, D-BUS-9, V2</td><td></td><td></td>
</tr>
<tr>
<td>30</td><td><code>sys_rdata_i</code></td><td>Sys_ctrl</td><td>Input</td><td>sys_ctrl to Sysbus</td>
<td>16 bits. sys_ctrl read data from a flop (off_q), valid in the clock after a read with sys_req_o = 1 (W+1); the flop may load every clock. Any value in other clocks.</td>
<td>2402</td><td>Assume: sys_rdata_i is free in every clock; its value in the clock after a read with sys_req_o = 1 is that read's data.</td><td>Bus target scoreboard (samples sys_rdata_i in W+1)</td><td>Impl spec §3 port table, requirements on neighbours, Sys_ctrl spec §2.1, BUS-02</td><td></td><td></td>
</tr>
<tr>
<td>31</td><td><code>sc_rdata_i</code></td><td>Sub-cores</td><td>Input</td><td>Sub-cores to Sysbus</td>
<td>64 bits, {SC3, SC2, SC1, SC0}: sub-core n's read data (xr_q) is sc_rdata_i[16n+15:16n], valid in the clock after a read with sc_req_o[n] = 1 (W+1); the flops may load every clock. Any value in other clocks.</td>
<td>2403</td><td>Assume: sc_rdata_i is free in every clock; for n = 0..3, its slice sc_rdata_i[16n+15:16n] in the clock after a read with sc_req_o[n] = 1 is that read's data.</td><td>Bus target scoreboard (samples the slice of sub-core n in W+1)</td><td>Impl spec §3 port table, requirements on neighbours, Subcore spec §3, Integration spec u_bus, BUS-02</td><td></td><td></td>
</tr>
<tr>
<td>32</td><td><code>pl_rdata_i</code></td><td>Pin layer</td><td>Input</td><td>Pin layer to Sysbus</td>
<td>16 bits. Pin layer read data from a flop (xr_q), valid in the clock after a read with pl_req_o = 1 (W+1); the flop may load every clock. Any value in other clocks.</td>
<td>2404</td><td>Assume: pl_rdata_i is free in every clock; its value in the clock after a read with pl_req_o = 1 is that read's data.</td><td>Bus target scoreboard (samples pl_rdata_i in W+1)</td><td>Impl spec §3 port table, requirements on neighbours, Pin_layer spec §3, BUS-02</td><td></td><td></td>
</tr>
</tbody>
</table>
