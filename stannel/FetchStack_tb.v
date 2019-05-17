`include "defaults.vh"

module FetchStack_tb();
  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  reg clk = 0;
  always #1 clk <= ~clk;

  wire [addrBits-1:0] address;
  wire [dataBits-1:0] dataIn;
  wire [dataBits-1:0] dataOut;
  wire                rw = `RAM_READ;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile("fetch_test_data.hex")) ram0 (
    .clk(clk),
    .address(address),
    .readWriteMode(rw),
    .dataIn(dataIn),
    .dataOut(dataOut)
  );

  reg reset = 0;
  wire finished;

  reg [addrBits-1:0] stackPointer;

  wire [dataBits-1:0] topOfStack1;
  wire [dataBits-1:0] topOfStack2;
  wire [dataBits-1:0] topOfStack3;

  FetchStack #(.addrBits(addrBits), .dataBits(dataBits)) fetch0 (
      // Section: operational I/Os
      .clk(clk),
      .reset(reset),
      .dataOut(dataOut),
      .address(address),
      .finished(finished),
      // Section: feature I/Os
      .stackPointer(stackPointer),
      .topOfStack1(topOfStack1),
      .topOfStack2(topOfStack2),
      .topOfStack3(topOfStack3)
    );

  initial begin
    $dumpfile("FetchStack_tb.vcd");
    $dumpvars(0, FetchStack_tb);

    stackPointer = 8;
    #4 reset = 1;

    #6 if (topOfStack1 != ram0.ram[stackPointer]) $error("Top of stack 1 not copied as expected.");
       if (topOfStack2 != ram0.ram[stackPointer + 1]) $error("Top of stack 2 not copied as expected.");
       if (topOfStack3 != ram0.ram[stackPointer + 2]) $error("Top of stack 3 not copied as expected.");

    #4 $finish;
  end

endmodule
