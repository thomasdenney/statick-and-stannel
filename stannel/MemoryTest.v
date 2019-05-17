`include "defaults.vh"
`include "opcodes.vh"
`include "status.vh"

module MemoryTest #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    input  wire                clk,
    input  wire                reset,
    input  wire [dataBits-1:0] ramDataOut,
    output wire                ramReadWriteMode,
    output wire [dataBits-1:0] ramDataIn,
    output wire [addrBits-1:0] ramAddress,
    output wire                finished
  );

  // State 0: Initate read
  // State 1: Allow read to complete
  // State 2: Register the read data and start write transaction
  // State 3: Allow write transaction to complete

  reg [0:1] state;
  always @(posedge clk)
    if (!reset)
      state <= 0;
    else
      state <= state + 1;

  reg [dataBits-1:0] rDataRead;
  always @(posedge clk)
    if (state == 1)
      rDataRead <= ramDataOut;

  always @(posedge clk)
    if (!reset)
      rAddress <= 0;
    else if (state == 3)
      rAddress <= rAddress + 1;

  reg [addrBits-1:0] rAddress;

  // Swaps data round; this is just to verify that switching the address doesn't corrupt other data
  assign ramAddress = state > 1 ? 16'hFFFF - rAddress : rAddress;
  assign ramReadWriteMode = state > 1 ? `RAM_WRITE : `RAM_READ;
  assign ramDataIn = rDataRead;

  assign finished = &rAddress && state == 3;

endmodule
