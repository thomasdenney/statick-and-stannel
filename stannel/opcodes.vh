// Major opcodes
`define OP_ALU                4'b0000
`define OP_PUSH               4'b0001
`define OP_ADD_SMALL          4'b0010
`define OP_PUSH_NEXT_LOWER    4'b0011
`define OP_PUSH_NEXT_UPPER    4'b0100
`define OP_JUMP               4'b0101
`define OP_PROCESS            4'b0110
`define OP_FUNCTION           4'b0111
`define OP_STACK              4'b1000

`ifdef ALLOW_ARBITRARY_STACK_READS
`define OP_READ_LOCAL         4'b1100
`define OP_READ_LOCAL_OFFSET  4'b1110
`endif

`ifdef ALLOW_ARBITRARY_STACK_WRITES
`define OP_WRITE_LOCAL        4'b1101
`define OP_WRITE_LOCAL_OFFSET 4'b1111
`endif

// Operand parts
// Always written as 4-bit constants so concatenation works

`define OP_ALU_ADD                    4'd0
`define OP_ALU_SUB                    4'd1
`define OP_ALU_TIMES_UNIMPLEMENTED    4'd2
`define OP_ALU_DIV_UNIMPLMENETED      4'd3
`define OP_ALU_ASL_UNIMPLEMENTED      4'd4
`define OP_ALU_ASR_UNIMPLEMENTED      4'd5
`define OP_ALU_LSL_UNIMPLEMENTED      4'd6
`define OP_ALU_LSR_UNIMPLEMENTED      4'd7
`define OP_ALU_NOT                    4'd8
`define OP_ALU_AND                    4'd9
`define OP_ALU_OR                     4'd10
`define OP_ALU_XOR                    4'd11
`define OP_ALU_TEST                   4'd14
`define OP_ALU_COMPARE                4'd15

// Only includes the upper three bits; see the Rust simulator for defs.
`define OP_CONDITION_ZERO_EQUAL                 4'b0000
`define OP_CONDITION_NOT_ZERO_NOT_EQUAL         4'b0001
`define OP_CONDITION_NEGATIVE                   4'b0010
`define OP_CONDITION_NON_NEGATIVE               4'b0011
`define OP_CONDITION_UNSIGNED_GREATER           4'b0100
`define OP_CONDITION_UNSIGNED_LESS_OR_EQUAL     4'b0101
`define OP_CONDITION_UNSIGNED_GREATER_OR_EQUAL  4'b0110
`define OP_CONDITION_UNSIGNED_LESS              4'b0111
`define OP_CONDITION_SIGNED_GREATER             4'b1000
`define OP_CONDITION_SIGNED_LESS_OR_EQUAL       4'b1001
`define OP_CONDITION_SIGNED_GREATER_OR_EQUAL    4'b1010
`define OP_CONDITION_SIGNED_LESS                4'b1011
`define OP_CONDITION_OVERFLOW                   4'b1100
`define OP_CONDITION_NO_OVERFLOW                4'b1101
`define OP_CONDITION_NEVER                      4'b1110
`define OP_CONDITION_ALWAYS                     4'b1111

`define OP_CONDITION_ZERO_EQUAL_UPPER_BITS                 3'b000
`define OP_CONDITION_NEGATIVE_UPPER_BITS                   3'b001
`define OP_CONDITION_UNSIGNED_GREATER_UPPER_BITS           3'b010
`define OP_CONDITION_UNSIGNED_GREATER_OR_EQUAL_UPPER_BITS  3'b011
`define OP_CONDITION_SIGNED_GREATER_UPPER_BITS             3'b100
`define OP_CONDITION_SIGNED_GREATER_OR_EQUAL_UPPER_BITS    3'b101
`define OP_CONDITION_OVERFLOW_UPPER_BITS                   3'b110
`define OP_CONDITION_NEVER_UPPER_BITS                      3'b111

// Deliberately defined as 3 bit constants
`define OP_STACK_DROP 4'b0000
`define OP_STACK_DUP  4'b0001
`define OP_STACK_SWAP 4'b0010
`define OP_STACK_TUCK 4'b0011
`define OP_STACK_ROT  4'b0100

`define OP_PROCESS_START           4'd0
`define OP_PROCESS_END             4'd1
`define OP_PROCESS_SEND            4'd2
`define OP_PROCESS_RECEIVE         4'd3
`define OP_PROCESS_ALT_START       4'd4
`define OP_PROCESS_ALT_WAIT        4'd5
`define OP_PROCESS_ALT_END         4'd6
`define OP_PROCESS_ENABLE_CHANNEL  4'd7
`define OP_PROCESS_DISABLE_CHANNEL 4'd8
`define OP_PROCESS_CREATE_CHANNEL  4'd9
`define OP_PROCESS_DESTROY_CHANNEL 4'd10
`define OP_PROCESS_YIELD           4'd11

`define OP_FUNCTION_CALL   4'b0000
`define OP_FUNCTION_RETURN 4'b0001

