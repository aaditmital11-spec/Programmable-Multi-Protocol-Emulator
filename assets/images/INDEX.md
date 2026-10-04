# Image index

Every image in this folder, what it shows, and the numbers visible in it.

## FPGA (Quartus, MAX 10 10M50DAF484C7G)

| File | What it shows |
|---|---|
| [programmable_6proto_flow_summary_557le.png](fpga_quartus/programmable_6proto_flow_summary_557le.png) | Programmable design, 6 protocols: 557 LEs, 165 registers, 1,024 memory bits (program memory in block RAM). |
| [programmable_6proto_flow_summary_557le_build2.png](fpga_quartus/programmable_6proto_flow_summary_557le_build2.png) | Second build of the same programmable design: 557 LEs, 165 registers, 1,024 memory bits. |
| [programmable_6proto_flow_summary_557le_build3.png](fpga_quartus/programmable_6proto_flow_summary_557le_build3.png) | Third build of the programmable design (from the conventional+jtag folder): 557 LEs. |
| [programmable_6proto_le_breakdown.png](fpga_quartus/programmable_6proto_le_breakdown.png) | Programmable design LE breakdown (557 total). Footnote: registers inside RAM blocks are not counted. |
| [programmable_6proto_setup_slack_9p537ns.png](fpga_quartus/programmable_6proto_setup_slack_9p537ns.png) | Programmable design timing: +9.537 ns setup slack, slow 1200mV 85C model, 50 MHz. |
| [programmable_6proto_setup_slack_9p537ns_build2.png](fpga_quartus/programmable_6proto_setup_slack_9p537ns_build2.png) | Same +9.537 ns setup slack from a second programmable build. |
| [programmable_hierarchy_memory_as_registers.png](fpga_quartus/programmable_hierarchy_memory_as_registers.png) | Per-module breakdown with program memory built from registers instead of RAM: 1,299 ALUTs, 1,188 registers, program_memory alone 752 ALUTs + 1,024 registers. |
| [programmable_core_technology_map.png](fpga_quartus/programmable_core_technology_map.png) | Post-mapping technology map view of the shared protocol core. |
| [programmable_top_rtl_source.png](fpga_quartus/programmable_top_rtl_source.png) | protocol_emulator_top.v open in the Quartus editor. |
| [programmable_v3_flow_summary_592le.png](fpga_quartus/programmable_v3_flow_summary_592le.png) | protocol_emulator_v3 build: 592 LEs, 149 registers, 1,024 memory bits. |
| [programmable_v3_setup_slack_9p168ns.png](fpga_quartus/programmable_v3_setup_slack_9p168ns.png) | protocol_emulator_v3 timing: +9.168 ns setup slack. |
| [early_build_timing_failure_neg8p624ns.png](fpga_quartus/early_build_timing_failure_neg8p624ns.png) | Early build that failed timing: -8.624 ns setup slack, TNS -1178.026 ns. Shows the before state. |
| [setup_slack_5p853ns_crop.png](fpga_quartus/setup_slack_5p853ns_crop.png) | Cropped setup summary showing +5.853 ns. Which build this is from is not visible in the image. |
| [conventional_3proto_flow_summary_347le.png](fpga_quartus/conventional_3proto_flow_summary_347le.png) | Hard-coded baseline (conventional_protocol_baseline): 347 LEs, 125 registers, 0 memory bits. |
| [conventional_3proto_setup_slack_11p683ns.png](fpga_quartus/conventional_3proto_setup_slack_11p683ns.png) | Hard-coded baseline timing: +11.683 ns setup slack. |
| [conventional_4proto_setup_slack_12p159ns.png](fpga_quartus/conventional_4proto_setup_slack_12p159ns.png) | Hard-coded 4-protocol build (4pro folder): +12.159 ns setup slack. |
| [conventional_5proto_setup_slack_10p964ns.png](fpga_quartus/conventional_5proto_setup_slack_10p964ns.png) | Hard-coded 5-protocol build (5pro folder): +10.964 ns setup slack. |
| [conventional_6proto_flow_summary_762le.png](fpga_quartus/conventional_6proto_flow_summary_762le.png) | Hard-coded 6-protocol build: 762 LEs, 281 registers, 96 pins, 0 memory bits. |
| [conventional_6proto_setup_slack_11p532ns.png](fpga_quartus/conventional_6proto_setup_slack_11p532ns.png) | Hard-coded 6-protocol timing: +11.532 ns setup slack. |
| [de10lite_programmer_usb_blaster.png](fpga_quartus/de10lite_programmer_usb_blaster.png) | Quartus Programmer with USB-Blaster connected, 10M50DAF484 detected, DE10-Lite bitstream loaded. |

## Simulation waveforms (Icarus + GTKWave)

| File | What it shows |
|---|---|
| [uart_program_load_and_start.png](simulation_gtkwave/uart_program_load_and_start.png) | UART: program words written through prog_we, then run asserted and pin 0 starts the frame. |
| [spi_mode0_tx_0xA5.png](simulation_gtkwave/spi_mode0_tx_0xA5.png) | SPI: spi_captured builds 01, 02, 05, 0A, 14, 29, 52, A5 bit by bit; halts at PC=9. |
| [i2c_start_addr_0xA0_ack_stop.png](simulation_gtkwave/i2c_start_addr_0xA0_ack_stop.png) | I2C: start_seen, address_byte = A0 over 8 edges, slave_ack_low pulse, stop_seen; halts at PC=0x15 (21). |
| [ps2_program_load_and_run.png](simulation_gtkwave/ps2_program_load_and_run.png) | PS/2: program load (prog_we pulses) followed by run and the start of the frame. |
| [ps2_frame_0xA5_odd_parity.png](simulation_gtkwave/ps2_frame_0xA5_odd_parity.png) | PS/2: full 11-bit frame captured edge by edge, then halted. |
| [ps2_frame_capture_zoom.png](simulation_gtkwave/ps2_frame_capture_zoom.png) | PS/2: closer view of the frame capture and edge_count. |
| [swd_full_transaction_overview.png](simulation_gtkwave/swd_full_transaction_overview.png) | SWD: whole transaction from program load to payload. |
| [swd_request_0x81.png](simulation_gtkwave/swd_request_0x81.png) | SWD: 8 request edges, request_seen = 0x81. |
| [swd_ack_and_turnaround.png](simulation_gtkwave/swd_ack_and_turnaround.png) | SWD: ack_phase and ack_index, line released (Z) during turnaround, payload starts. |
| [swd_payload_middle.png](simulation_gtkwave/swd_payload_middle.png) | SWD: payload bits 5 to 20 shifting in (write_data_seen building up). |
| [swd_payload_0xA5C33C5A_and_parity.png](simulation_gtkwave/swd_payload_0xA5C33C5A_and_parity.png) | SWD: 32 data edges, write_data_seen = A5C33C5A, parity edge, halt. |
| [jtag_dr_scan_overview.png](simulation_gtkwave/jtag_dr_scan_overview.png) | JTAG: program load, TAP state walk (tap_state), 8 scan edges. |

## RTL excerpts

| File | What it shows |
|---|---|
| [protocol_core_excerpt.png](rtl/protocol_core_excerpt.png) | Excerpt of protocol_core.v execution logic. |
| [program_loader_excerpt.png](rtl/program_loader_excerpt.png) | Excerpt of program_loader.v (two bytes in, one 16-bit word out). |

## ASIC layout (IHP CMOS5L via Tiny Tapeout)

| File | What it shows |
|---|---|
| [gds_active_region.png](asic_gds/gds_active_region.png) | Zoom on the placed and routed logic. |
| [gds_full_tile_render.png](asic_gds/gds_full_tile_render.png) | Full 6x4 tile render, including fill. |
| [gds_layout_viewer_screenshot.png](asic_gds/gds_layout_viewer_screenshot.png) | Layout viewer screenshot. |
| [gds_full_tile_render_highres.png](asic_gds/gds_full_tile_render_highres.png) | High-resolution full render (12893 x 7107 px). |
