`include "defaults.vh"

module Enable_tb();
  // Clock
  reg clk;
  always #1 clk = clk !== 1'b1;

  // Memory
  parameter romFile = "zeroes.hex";

  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  reg  [addrBits-1:0] address;
  reg  [dataBits-1:0] dataIn;
  wire [dataBits-1:0] dataOut;
  reg                 readWriteMode;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(romFile)) memory (
    .clk          (clk),
    .address      (address),
    .readWriteMode(readWriteMode),
    .dataIn       (dataIn),
    .dataOut      (dataOut)
  );

  // Test component
  reg                reset = 0;
  reg [addrBits-1:0] channel = 2;
  reg [addrBits-1:0] rxPid = 1;
  reg                finished;
  reg                rxCanReceive;

  Enable #(.addrBits(addrBits), .dataBits(dataBits)) e0 (
    .clk          (clk),
    .reset        (reset),
    .finished     (finished),
    .address      (address),
    .readWriteMode(readWriteMode),
    .dataOut      (dataOut),
    .dataIn       (dataIn),
    .channel      (channel),
    .rxPid        (rxPid),
    .rxCanReceive (rxCanReceive)
  );

  task enableWithNoSender;
    begin
      reset <= 1;
      @(posedge finished)
        begin
          reset <= 0;
          if (rxCanReceive) $error("Should not be able to receive");
          if (memory.ram[2] != rxPid) $error("Should have written rx pid to memory");
        end
    end
  endtask

  task enableWithSender;
    begin
      reset <= 1;
      memory.ram[2] <= 3;
      @(posedge finished)
        begin
          reset <= 0;
          if (!rxCanReceive) $error("Should be able to receive");
          if (memory.ram[2] != 3) $error("Should have retained sender in memory");
        end
    end
  endtask

  initial begin
    $dumpfile("Enable_tb.vcd");
    $dumpvars(0, Enable_tb);

    #2 enableWithNoSender;
    #2 enableWithSender;

    #2 $finish;
  end
endmodule
