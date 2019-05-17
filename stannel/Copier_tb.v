`include "defaults.vh"

module Copier_tb();
  parameter srcFile = "../programs/hexes/resume_untested.hex";
  parameter dstFile = "zeroes.hex";

  reg clk;
  always #1 clk = clk !== 1'b1;

  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  wire [addrBits-1:0] readAddress;
  wire [dataBits-1:0] readDataIn;
  wire [dataBits-1:0] readDataOut;
  wire                readReadWriteMode;

  wire [addrBits-1:0] writeAddress;
  wire [dataBits-1:0] writeDataIn;
  wire [dataBits-1:0] writeDataOut;
  wire                writeReadWriteMode;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(srcFile)) read (
    .clk(clk),
    .address(readAddress),
    .readWriteMode(readReadWriteMode),
    .dataIn(readDataIn),
    .dataOut(readDataOut)
  );

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(dstFile)) write (
    .clk(clk),
    .address(writeAddress),
    .readWriteMode(writeReadWriteMode),
    .dataIn(writeDataIn),
    .dataOut(writeDataOut)
  );

  reg reset = 0;
  wire finished;
  wire [addrBits-1:0] startReadAddress = 8'h70;
  wire [addrBits-1:0] numberOfWordsToCopy = 3;
  wire [addrBits-1:0] startWriteAddress = 8'hFD;

  Copier #(.addrBits(addrBits), .dataBits(dataBits)) copier0(
    .clk(clk),
    .reset(reset),
    .finished(finished),
    .readAddress(readAddress),
    .readReadWriteMode(readReadWriteMode),
    .readDataOut(readDataOut),
    .writeAddress(writeAddress),
    .writeReadWriteMode(writeReadWriteMode),
    .writeDataIn(writeDataIn),
    .startReadAddress(startReadAddress),
    .numberOfWordsToCopy(numberOfWordsToCopy),
    .startWriteAddress(startWriteAddress)
  );

  initial begin
    $dumpfile("Copier_tb.vcd");
    $dumpvars(0, Copier_tb);
    // Deliberately waiting a cycle to make it really obvious when the start happens and what
    // the result is after the reset occurs.
    #3 reset <= 1;
    // This will print on every fetch
    @(posedge finished)
      begin
        if (write.ram[8'hFD] != read.ram[8'h70]) $error("Memory value 1");
        if (write.ram[8'hFE] != read.ram[8'h71]) $error("Memory value 2");
        if (write.ram[8'hFF] != read.ram[8'h72]) $error("Memory value 3");
        $finish;
      end
  end
endmodule
