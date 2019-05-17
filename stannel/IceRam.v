`include "defaults.vh"

// This replaces the previous genram component. This is designed to use a single BRAM block in its
// default configuration and offers a slightly easier interface for using it.
// This module is based on "Memory Usage Guide for iCE40 Devices"
module IceRam #(parameter addrBits = 8, parameter dataBits = 16) (
    input  wire clk,
    input  wire [addrBits-1:0] address,
    input  wire readWriteMode,
    input  wire [dataBits-1:0] dataIn,
    output wire [dataBits-1:0] dataOut
  );

  parameter romFile = "zeroes.hex";

  localparam ramSize = 2 ** addrBits;
  reg [dataBits-1:0] ram[0:ramSize-1];

  reg [dataBits-1:0] rDataOut;

  always @(posedge clk)
    begin
      if (readWriteMode == `RAM_WRITE)
        ram[address] <= dataIn;
      rDataOut <= ram[address];
    end

  assign dataOut = rDataOut;

  initial $readmemh(romFile, ram);
endmodule
