`include "defaults.vh"

// The inputs and outputs of this stage are already registered. The first four
// bytes of memory are used as follows:
//  0. The stack pointer
//  1. The call stack pointer
//  2. The upper four bits are the ALU flags, the LSB is the MSB of the PC
//  3. The least significant eight bits of the PC
module SaveState #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    output wire [dataBits-1:0] dataIn,
    output wire [addrBits-1:0] address,
    output wire                rwMode,
    output wire                finished,
    // Section: feature inputs
    input  wire [addrBits-1:0] stackPointer,
    input  wire [addrBits-1:0] callStackPointer,
    input  wire [8:0]          programCounter,
    input  wire [3:0]          aluFlags,
    input  wire [dataBits-1:0] topOfStack1,
    input  wire [dataBits-1:0] topOfStack2,
    input  wire [dataBits-1:0] topOfStack3
  );

  // Section: Data path

  reg [dataBits-1:0] wDataIn;
  assign dataIn = wDataIn;
  reg [addrBits-1:0] wAddress;
  assign address = wAddress;

  assign rwMode = reset && !finished ? `RAM_WRITE : `RAM_READ;

  reg rRamCycle;
  reg [2:0] rState;

  localparam SAVE_STACK_1                 = 3'd0;
  localparam SAVE_STACK_2                 = 3'd1;
  localparam SAVE_STACK_3                 = 3'd2;
  localparam SAVE_STACK_POINTERS          = 3'd3;
  localparam SAVE_PROGRAM_COUNTER_AND_ALU = 3'd4;
  localparam SAVE_DONE                    = 3'd5;

  assign finished = rState == SAVE_DONE;

  // Section: Controller

  always @(posedge clk)
  begin
    if (!reset)
      rRamCycle <= 0;
    else
      rRamCycle <= rRamCycle + 1;

    if (!reset)
      rState <= 0;
    else if (rRamCycle)
      rState <= rState + 1;
  end

  always @(*)
    case (rState)
      SAVE_STACK_1:
      begin
        wAddress = stackPointer + 0;
        wDataIn  = topOfStack1;
      end
      SAVE_STACK_2:
      begin
        wAddress = stackPointer + 1;
        wDataIn  = topOfStack2;
      end
      SAVE_STACK_3:
      begin
        wAddress = stackPointer + 2;
        wDataIn  = topOfStack3;
      end
      SAVE_STACK_POINTERS:
      begin
        wAddress = 0;
        wDataIn  = { stackPointer, callStackPointer - 8'd2 };
      end
      SAVE_PROGRAM_COUNTER_AND_ALU:
      begin
        wAddress = 1;
        wDataIn  = { aluFlags, 3'b0, programCounter };
      end
      default:
      begin
        wAddress = {addrBits{1'bx}};
        wDataIn  = {dataBits{1'bx}};
      end
    endcase
endmodule
