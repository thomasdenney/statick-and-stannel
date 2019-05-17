`include "defaults.vh"

module MessageDelivery_tb();
  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  reg clk = 0;
  always #1 clk <= ~clk;

  reg  [addrBits-1:0] address;
  reg  [dataBits-1:0] dataIn;
  wire [dataBits-1:0] dataOut;
  reg                 readWriteMode;

  // The simulation is done with only a single memory cell to avoid having to
  // test inverse memory module mappings.
  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile("zeroes.hex")) ram0 (
    .clk          (clk),
    .address      (address),
    .readWriteMode(readWriteMode),
    .dataIn       (dataIn),
    .dataOut      (dataOut)
  );

  reg reset = 0;
  wire finished;

  reg [addrBits-1:0] core0Process;
  reg [addrBits-1:0] core1Process;

  reg  [addrBits-1:0] targetProcess;
  reg  [dataBits-1:0] message;
  reg  needsJump;
  reg  [8:0]          jumpDestination;

  wire deliverMessageToCore0;
  wire deliverMessageToCore1;

  MessageDelivery #(.addrBits(addrBits), .dataBits(dataBits)) msg (
    // Section: operational I/Os
    .clk                    (clk),
    .reset                  (reset),
    .finished               (finished),

    .memoryCellReadWriteMode(readWriteMode),
    .memoryCellAddress      (address),
    .memoryCellDataIn       (dataIn),
    .memoryCellDataOut      (dataOut),

    .core0Process           (core0Process),
    .core1Process           (core1Process),

    .targetProcess          (targetProcess),
    .message                (message),
    .needsJump              (needsJump),
    .jumpDestination        (jumpDestination),
    .deliverMessageToCore0  (deliverMessageToCore0),
    .deliverMessageToCore1  (deliverMessageToCore1)
  );

  task deliverToCore0Test;
    begin
      reset           <= 1;
      core0Process    <= 1;
      core1Process    <= 2;
      targetProcess   <= 1;
      message         <= 16'd42;
      needsJump       <= 0;
      jumpDestination <= 9'bx;

      @(posedge finished)
        begin
          reset <= 0;
          if (deliverMessageToCore0 != 1) $error("Expected to deliver to core 0");
          if (deliverMessageToCore1) $error("Not expecting to deliver to core 1");
          if (ram0.ram[0] != 0) $error("Modified stack pointers");
          if (ram0.ram[1] != 0) $error("Modified program counter");
        end
    end
  endtask

  task deliverToCore1Test;
    begin
      reset         <= 1;
      targetProcess <= 2;

      @(posedge finished)
        begin
          reset <= 0;
          if (deliverMessageToCore0) $error("Not expecting to deliver to core 0");
          if (!deliverMessageToCore1) $error("Expecting to deliver to core 1");
          if (ram0.ram[0] != 0) $error("Modified stack pointers");
          if (ram0.ram[1] != 0) $error("Modified program counter");
        end
    end
  endtask

  task deliverToMemoryTest;
    begin
      reset         <= 1;
      targetProcess <= 3;

      @(posedge finished)
        begin
          reset <= 0;
          if (deliverMessageToCore0) $error("Not expecting to deliver to core 0");
          if (deliverMessageToCore1) $error("Not expecting to deliver to core 1");
          if (ram0.ram[0] != 16'hFF00) $error("Incorrect stack pointers");
          if (ram0.ram[1] != 0) $error("Modified program counter");
          if (ram0.ram[8'hFF] != message) $error("Didn't deliver message");
        end
    end
  endtask

  task deliverToMemoryAndJumpTest;
    begin
      reset           <= 1;
      needsJump       <= 1;
      jumpDestination <= 9'd42;

      @(posedge finished)
        begin
          reset <= 0;
          if (deliverMessageToCore0) $error("Not expecting to deliver to core 0");
          if (deliverMessageToCore1) $error("Not expecting to deliver to core 1");
          if (ram0.ram[0] != 16'hFE00) $error("Incorrect stack pointers");
          if (ram0.ram[1] != 16'd42) $error("Modified program counter");
          if (ram0.ram[8'hFE] != message) $error("Didn't deliver message");
        end
    end
  endtask

  initial begin
    $dumpfile("MessageDelivery_tb.vcd");
    $dumpvars(0, MessageDelivery_tb);

    #4 deliverToCore0Test;
    #4 deliverToCore1Test;
    #4 deliverToMemoryTest;
    #4 deliverToMemoryAndJumpTest;

    #4 $finish;
  end

endmodule
