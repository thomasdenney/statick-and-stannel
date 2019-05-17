`include "defaults.vh"

module SaveState_tb();
  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  reg clk = 0;
  always #1 clk <= ~clk;

  wire [addrBits-1:0] address;
  wire [dataBits-1:0] dataIn;
  wire [dataBits-1:0] dataOut;
  wire                rw;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile("fetch_test_data.hex")) ram0 (
    .clk(clk),
    .address(address),
    .readWriteMode(rw),
    .dataIn(dataIn),
    .dataOut(dataOut)
  );

  reg reset = 0;
  wire finished;

  wire [8:0]          programCounter   = 9'd42;
  wire [3:0]          aluFlags         = 4'b1010;
  wire [addrBits-1:0] callStackPointer = 8'd10;
  wire [addrBits-1:0] stackPointer     = 8'hF0;
  wire [dataBits-1:0] topOfStack1      = 16'd17;
  wire [dataBits-1:0] topOfStack2      = 16'd25;
  wire [dataBits-1:0] topOfStack3      = 16'd1234;

  SaveState #(.addrBits(addrBits), .dataBits(dataBits)) saveState0 (
      // Section: operational I/Os
      .clk(clk),
      .reset(reset),
      .dataIn(dataIn),
      .address(address),
      .rwMode(rw),
      .finished(finished),
      // Section: feature I/Os
      .programCounter(programCounter),
      .aluFlags(aluFlags),
      .callStackPointer(callStackPointer),
      .stackPointer(stackPointer),
      .topOfStack1(topOfStack1),
      .topOfStack2(topOfStack2),
      .topOfStack3(topOfStack3)
    );

  initial begin
    $dumpfile("SaveState_tb.vcd");
    $dumpvars(0, SaveState_tb);

    #4 reset = 1;

    @(posedge finished)
      begin
        reset = 0;
        #4 $finish;
      end

  end

endmodule
