`default_nettype none

`include "timing.vh"

`define ADDRESS_BITS 8
`define DATA_BITS 16

`define RAM_WRITE 1'b0
`define RAM_READ  1'b1

`define ICE_STICK_CLOCK_RATE 16000000
`define BLACK_ICE_CLOCK_RATE 32000000

// The value of this is only used in the utility scripts. This macro should
// never be defined if just using a single core.
`define MULTI_CORE 2

// The actual number of cells defined using the memory controller must be one
// greater than this, because processes are allocated starting from 1, not 0.
// Only wires related to the memory controller must be kept in sync with this
// number.
`define CELL_COUNT 16
`define CELL_COUNT_CONST_1 {{`CELL_COUNT{1'b0}}, 1'b1}

// Comment out the lines below to disable the instructions
`define ALLOW_ARBITRARY_STACK_READS
// `define ALLOW_ARBITRARY_STACK_WRITES

`define USER_CORE_0           3'd0
`define USER_CORE_1           3'd1
`define USER_CORE_DUMPER      3'd2
`define USER_PROCESSOR_0      3'd4
`define USER_PROCESSOR_1      3'd5
`define USER_UNUSED           3'd7
