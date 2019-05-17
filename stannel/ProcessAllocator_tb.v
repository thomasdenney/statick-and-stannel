`include "defaults.vh"

module ProcessAllocator_tb;

  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  reg clk;
  always #1 clk <= clk !== 1'b1;

  reg reset = 0;
  reg enabled;
  reg finished;

  wire [addrBits-1:0] oldAddress;
  wire [dataBits-1:0] oldDataIn;
  wire [dataBits-1:0] oldDataOut;
  wire                oldReadWriteMode;

  wire [addrBits-1:0] newAddress;
  wire [dataBits-1:0] newDataIn;
  wire [dataBits-1:0] newDataOut;
  wire                newReadWriteMode;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile("fetch_test_data.hex")) ramOld(
    .clk          (clk),
    .address      (oldAddress),
    .dataIn       (oldDataIn),
    .dataOut      (oldDataOut),
    .readWriteMode(oldReadWriteMode)
  );

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile("zeroes.hex")) ramNew(
    .clk          (clk),
    .address      (newAddress),
    .dataIn       (newDataIn),
    .dataOut      (newDataOut),
    .readWriteMode(newReadWriteMode)
  );

  reg [4:0]          targetMemoryCell;
  reg [addrBits-1:0] newPid;
  reg                hasProcessCreate;
  reg [addrBits-1:0] wordsToCopy;
  reg [8:0]          startProgramCounter;
  reg [addrBits-1:0] pidToFree;

  ProcessAllocator #(.addrBits(addrBits), .dataBits(dataBits)) allocator(
    .clk                 (clk),
    .reset               (reset),
    .enabled             (enabled),
    .finished            (finished),
    .hasProcessCreate    (hasProcessCreate),
    .wordsToCopy         (wordsToCopy),
    .startProgramCounter (startProgramCounter),
    .pidToFree           (pidToFree),
    .targetMemoryCell    (targetMemoryCell),
    .dataOutForOldStack  (oldDataOut),
    .addressForOldStack  (oldAddress),
    .readWriteForOldStack(oldReadWriteMode),
    .dataInForOldStack   (oldDataIn),
    .dataInForNewStack   (newDataIn),
    .addressForNewStack  (newAddress),
    .readWriteForNewStack(newReadWriteMode),
    .newPid              (newPid)
  );

  task initialiseProcess1Test;
    begin
      hasProcessCreate    <= 1;
      wordsToCopy         <= 0;
      startProgramCounter <= 0;
      enabled             <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (newPid != 1) $error("Expect first PID to be 1");
          if (targetMemoryCell != newPid) $error("Target memory cell and new PID should be the same");
          if (ramNew.ram[0] != 16'h0000) $error("Stack pointers should be initialised to zero, not %4h", ramNew.ram[0]);
          if (ramNew.ram[1] != 16'h0000) $error("Program counter and ALU flags should be initialised to zero, not %4h", ramNew.ram[1]);
        end
    end
  endtask

  task initialiseProcess2Test;
    begin
      hasProcessCreate    <= 1;
      wordsToCopy         <= 5;
      startProgramCounter <= 7;
      enabled             <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (newPid != 2) $error("Expect second PID to be 2");
          if (targetMemoryCell != newPid) $error("Target memory cell and new PID should be the same");
          if (ramNew.ram[0] != 16'hFB00) $error("Stack pointer not correct");
          if (ramNew.ram[1] != 16'h07) $error("New program counter not correct");
          if (ramNew.ram[8'hFB] != ramOld.ram[8'hFB]) $error("Element FB doesn't match");
          if (ramNew.ram[8'hFC] != ramOld.ram[8'hFC]) $error("Element FC doesn't match");
          if (ramNew.ram[8'hFD] != ramOld.ram[8'hFD]) $error("Element FD doesn't match");
          if (ramNew.ram[8'hFE] != ramOld.ram[8'hFE]) $error("Element FE doesn't match");
          if (ramNew.ram[8'hFF] != ramOld.ram[8'hFF]) $error("Element FF doesn't match");
          if (ramOld.ram[0] != 16'h0501) $error("Old stack pointer not updated correctly");
        end
    end
  endtask

  task freeProcess2Test;
    begin
      hasProcessCreate <= 0;
      pidToFree        <= 2;
      enabled          <= 1;
      @(posedge finished)
        enabled <= 0;
    end
  endtask

  task freeProcess1Test;
    begin
      pidToFree        <= 1;
      enabled          <= 1;
      @(posedge finished)
        enabled <= 0;
    end
  endtask

  initial
    begin
      $dumpfile("ProcessAllocator_tb.vcd");
      $dumpvars(0, ProcessAllocator_tb);

      #2 reset <= 1;
      #4 initialiseProcess1Test;
      #4 initialiseProcess2Test;
      #4 freeProcess2Test;
      #4 freeProcess1Test;

      #2 $finish;
    end

endmodule
