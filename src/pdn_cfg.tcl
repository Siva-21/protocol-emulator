# Power grid of the Protocol Emulator (LibreLane PDN_CFG, run by OpenROAD.GeneratePDN).
#
# Derived from LibreLane's default pdn_cfg.tcl (single-layer grid, as the Tiny
# Tapeout template sets it: Metal1 rails, vertical Metal4 straps, no ring), with
# three changes for the SRAM macro RM_IHPSG13_1P_512x16_c2_bm_bist of main_ss:
#
# 1. No macro grid. The macro's VDD!, VDDARRAY! and VSS! pins are vertical Metal4
#    stripes (full macro height, 11.24 um pitch) and the macro blocks Metal1-3,
#    so there is no layer to via from. The stock macro grid needs
#    Metal4 -> TopMetal1 vias, and TopMetal1 is reserved for the chip-level grid on
#    sg13cmos5l (PDN-0232 / PDN-0233). The macro is connected by Metal4 overlap
#    instead: a project strap lies on top of a pin of the same net.
#
# 2. Strap pitch 44.96 um (= 4 x the macro's pin pitch), pair gap 3.52 um. With
#    the template's pitch 50 no macro position avoids every wrong-net pin. With
#    this pitch and the macro at x = 107.52 um (config.json), 5 VPWR and 5 VGND
#    straps land on pins of their own net, and every other strap crosses the macro
#    in a gap at least 1.4 um from the nearest pin.
#
# 3. pdngen cuts every strap that crosses a macro (a piece below, a piece above).
#    The Tiny Tapeout precheck needs each power pin to reach both the top and
#    the bottom edge (pin_check.py), so the cut straps are bridged again with
#    Metal4 stripes of the same net. A check then fails the step, loudly, if any
#    bridged strap is closer than 0.5 um to a macro pin of the other net, closer
#    than 0.24 um to one of its own net without touching it, or if a macro power
#    pin is left unconnected. Run it again whenever the macro, the pitch or the
#    offset change.

source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections

set secondary []
foreach vdd $::env(VDD_NETS) gnd $::env(GND_NETS) {
    if { $vdd != $::env(VDD_NET)} {
        lappend secondary $vdd

        set db_net [[ord::get_db_block] findNet $vdd]
        if {$db_net == "NULL"} {
            set net [odb::dbNet_create [ord::get_db_block] $vdd]
            $net setSpecial
            $net setSigType "POWER"
        }
    }

    if { $gnd != $::env(GND_NET)} {
        lappend secondary $gnd

        set db_net [[ord::get_db_block] findNet $gnd]
        if {$db_net == "NULL"} {
            set net [odb::dbNet_create [ord::get_db_block] $gnd]
            $net setSpecial
            $net setSigType "GROUND"
        }
    }
}

set_voltage_domain -name CORE -power $::env(VDD_NET) -ground $::env(GND_NET) \
    -secondary_power $secondary

if { $::env(PDN_MULTILAYER) == 1 || $::env(PDN_CORE_RING) == 1 } {
    throw APPLICATION "src/pdn_cfg.tcl supports only the single-layer grid without a core ring (PDN_MULTILAYER 0, PDN_CORE_RING 0)."
}

# ---- Metal4 straps (see 2.)
set pe_strap_pitch   44.96
set pe_strap_spacing 3.52

set arg_list [list]
if { $::env(PDN_ENABLE_PINS) } {
    lappend arg_list -pins "$::env(PDN_VERTICAL_LAYER)"
}

define_pdn_grid \
    -name stdcell_grid \
    -starts_with POWER \
    -voltage_domain CORE \
    {*}$arg_list

set arg_list [list]
if { $::env(PDN_EXTEND_TO) eq "core_ring" } {
    lappend arg_list -extend_to_core_ring
} elseif { $::env(PDN_EXTEND_TO) eq "boundary" } {
    lappend arg_list -extend_to_boundary
}

add_pdn_stripe \
    -grid stdcell_grid \
    -layer $::env(PDN_VERTICAL_LAYER) \
    -width $::env(PDN_VWIDTH) \
    -pitch $pe_strap_pitch \
    -offset $::env(PDN_VOFFSET) \
    -spacing $pe_strap_spacing \
    -starts_with POWER \
    {*}$arg_list

# ---- standard cell rails
if { $::env(PDN_ENABLE_RAILS) == 1 } {
    add_pdn_stripe \
        -grid stdcell_grid \
        -layer $::env(PDN_RAIL_LAYER) \
        -width $::env(PDN_RAIL_WIDTH) \
        -followpins

    add_pdn_connect \
        -grid stdcell_grid \
        -layers "$::env(PDN_RAIL_LAYER) $::env(PDN_VERTICAL_LAYER)"
}

# ---- macro connection by Metal4 overlap (see 1. and 3.)
proc pe_macro_power_instances {} {
    set result {}
    foreach inst [[ord::get_db_block] getInsts] {
        if { [[$inst getMaster] isBlock] } {
            lappend result $inst
        }
    }
    return $result
}

# Vertical pieces of the straps of both power nets that cross the x range of a macro,
# as {net xmin xmax ymin ymax swire} in database units.
proc pe_strap_pieces {layer_name x0 x1} {
    set pieces {}
    foreach net_name [list $::env(VDD_NET) $::env(GND_NET)] {
        set net [[ord::get_db_block] findNet $net_name]
        foreach sw [$net getSWires] {
            foreach b [$sw getWires] {
                if { [$b isVia] || [[$b getTechLayer] getName] ne $layer_name } {
                    continue
                }
                if { [$b xMax] <= $x0 || [$b xMin] >= $x1 } {
                    continue
                }
                if { ([$b yMax] - [$b yMin]) <= ([$b xMax] - [$b xMin]) } {
                    continue
                }
                lappend pieces [list $net_name [$b xMin] [$b xMax] [$b yMin] [$b yMax] $sw]
            }
        }
    }
    return $pieces
}

# Fill the gap pdngen leaves in a strap above and below a macro.
proc pe_bridge_macro_straps {layer_name} {
    set tech [ord::get_db_tech]
    set layer [$tech findLayer $layer_name]
    set dbu [[ord::get_db_block] getDbUnitsPerMicron]
    set overlap [expr {int(0.48 * $dbu)}]
    set bridged 0
    foreach inst [pe_macro_power_instances] {
        set bb [$inst getBBox]
        set my0 [$bb yMin]
        set my1 [$bb yMax]
        set pieces [pe_strap_pieces $layer_name [$bb xMin] [$bb xMax]]
        foreach lo $pieces {
            lassign $lo net xmin xmax ymin ymax sw
            if { $ymax > $my0 + $overlap } { continue }   ;# lower piece: ends at the macro
            foreach hi $pieces {
                lassign $hi net2 xmin2 xmax2 ymin2 ymax2 sw2
                if { $net2 ne $net || $xmin2 != $xmin || $xmax2 != $xmax || $ymin2 < $my1 - $overlap } {
                    continue
                }
                odb::dbSBox_create $sw $layer $xmin [expr {$ymax - $overlap}] $xmax [expr {$ymin2 + $overlap}] STRIPE
                incr bridged
                break
            }
        }
    }
    return $bridged
}

# Metal4 geometry of the power pins of a macro, as {net pin xmin xmax ymin ymax}.
proc pe_macro_power_pins {inst layer_name} {
    if { [$inst getOrient] ne "R0" } {
        throw APPLICATION "pdn_cfg.tcl: macro [$inst getName] must have orientation N (R0)."
    }
    set origin [$inst getOrigin]
    set ox [lindex $origin 0]
    set oy [lindex $origin 1]
    set result {}
    foreach it [$inst getITerms] {
        set net [$it getNet]
        if { $net eq "NULL" || ![string match "*\\!" [[$it getMTerm] getName]] } { continue }
        foreach mpin [[$it getMTerm] getMPins] {
            foreach box [$mpin getGeometry] {
                if { [$box isVia] || [[$box getTechLayer] getName] ne $layer_name } { continue }
                lappend result [list [$net getName] [[$it getMTerm] getName] \
                    [expr {$ox + [$box xMin]}] [expr {$ox + [$box xMax]}] \
                    [expr {$oy + [$box yMin]}] [expr {$oy + [$box yMax]}]]
            }
        }
    }
    return $result
}

proc pe_check_macro_power {layer_name} {
    set dbu [[ord::get_db_block] getDbUnitsPerMicron]
    set min_other [expr {int(0.50 * $dbu)}]    ;# strap to a pin of the other net
    set min_same  [expr {int(0.24 * $dbu)}]    ;# Metal4 spacing: same net, not touching
    set errors 0
    foreach inst [pe_macro_power_instances] {
        set bb [$inst getBBox]
        set pins [pe_macro_power_pins $inst $layer_name]
        if { [llength $pins] == 0 } {
            throw APPLICATION "pdn_cfg.tcl: no power pins on $layer_name found in macro [$inst getName]."
        }
        set connected [dict create]
        foreach pin $pins { dict set connected [lindex $pin 1] 0 }
        foreach pc [pe_strap_pieces $layer_name [$bb xMin] [$bb xMax]] {
            lassign $pc snet sx0 sx1 sy0 sy1 sw
            foreach pin $pins {
                lassign $pin pnet pname px0 px1 py0 py1
                if { $sy1 < $py0 || $sy0 > $py1 } { continue }
                set gap [expr {max($px0 - $sx1, $sx0 - $px1)}]
                if { $pnet eq $snet } {
                    if { $gap < 0 } {
                        dict incr connected $pname
                    } elseif { $gap < $min_same } {
                        puts stderr "\[ERROR\] pdn_cfg.tcl: $snet strap at x [expr {$sx0/double($dbu)}] is [expr {$gap/double($dbu)}] um from $pname of [$inst getName] (same net, needs touch or >= 0.24 um)."
                        incr errors
                    }
                } elseif { $gap < $min_other } {
                    puts stderr "\[ERROR\] pdn_cfg.tcl: $snet strap at x [expr {$sx0/double($dbu)}] is [expr {$gap/double($dbu)}] um from $pname ($pnet) of [$inst getName] (needs >= 0.5 um)."
                    incr errors
                }
            }
        }
        dict for {pname count} $connected {
            if { $count == 0 } {
                puts stderr "\[ERROR\] pdn_cfg.tcl: no strap overlaps any $pname pin of [$inst getName]."
                incr errors
            } else {
                puts "pdn_cfg.tcl: [$inst getName] $pname: $count pin shapes overlapped by a strap of the same net."
            }
        }
    }
    if { $errors > 0 } {
        throw APPLICATION "pdn_cfg.tcl: $errors macro power problem(s); move the macro (MACROS in config.json) or adjust the strap pitch."
    }
}

rename pdngen pe_pdngen_stock
proc pdngen {args} {
    pe_pdngen_stock {*}$args
    set layer $::env(PDN_VERTICAL_LAYER)
    puts "pdn_cfg.tcl: bridged [pe_bridge_macro_straps $layer] strap gap(s) over macros."
    pe_check_macro_power $layer
}
