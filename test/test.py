# SPDX-License-Identifier: Apache-2.0
# Placeholder top-level test for tt_um_protocol_emulator_placeholder:
# after reset, every output must be driven to a known 0.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_placeholder_outputs_low(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())  # 50 MHz

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    for name in ("uo_out", "uio_oe"):
        val = getattr(dut, name).value
        assert val.is_resolvable, f"{name} contains X/Z: {val}"
        assert val.to_unsigned() == 0, f"{name} = {val}, expected 0"
