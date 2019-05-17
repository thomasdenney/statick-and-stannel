`include "defaults.vh"

module Processor_tb;

  parameter romFile = "../programs/hexes/add.hex";

  reg clk;
  always #1 clk = clk !== 1'b1;
  reg reset = 0;
  reg finished;

  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;
  localparam ramSize = 2 ** addrBits;

  MemoryController17x6 #(.addrBits(addrBits), .dataBits(dataBits)) stackMemory(
    .clk           (clk),
    .address0      (core0Address),
    .address1      (core1Address),
    .address2      (dumpAddress),
    .address3      (unusedAddress),
    .address4      (processorInternal0Address),
    .address5      (processorInternal1Address),
    .readWriteMode0(core0ReadWriteMode),
    .readWriteMode1(core1ReadWriteMode),
    .readWriteMode2(dumpReadWriteMode),
    .readWriteMode3(unusedReadWriteMode),
    .readWriteMode4(processorInternal0ReadWriteMode),
    .readWriteMode5(processorInternal1ReadWriteMode),
    .dataIn0       (core0DataIn),
    .dataIn1       (core1DataIn),
    .dataIn2       (dumpDataIn),
    .dataIn3       (unusedDataIn),
    .dataIn4       (processorInternal0DataIn),
    .dataIn5       (processorInternal1DataIn),
    .dataOut0      (core0DataOut),
    .dataOut1      (core1DataOut),
    .dataOut2      (dumpDataOut),
    .dataOut3      (unusedDataOut),
    .dataOut4      (processorInternal0DataOut),
    .dataOut5      (processorInternal1DataOut),
    .cell0ToUser   (cell0ToUser),
    .cell1ToUser   (cell1ToUser),
    .cell2ToUser   (cell2ToUser),
    .cell3ToUser   (cell3ToUser),
    .cell4ToUser   (cell4ToUser),
    .cell5ToUser   (cell5ToUser),
    .cell6ToUser   (cell6ToUser),
    .cell7ToUser   (cell7ToUser),
    .cell8ToUser   (cell8ToUser),
    .cell9ToUser   (cell9ToUser),
    .cell10ToUser  (cell10ToUser),
    .cell11ToUser  (cell11ToUser),
    .cell12ToUser  (cell12ToUser),
    .cell13ToUser  (cell13ToUser),
    .cell14ToUser  (cell14ToUser),
    .cell15ToUser  (cell15ToUser),
    .cell16ToUser  (cell16ToUser)
  );

  wire [addrBits-1:0] dumpAddress;
  wire                dumpReadWriteMode;
  wire [dataBits-1:0] dumpDataIn;
  wire [dataBits-1:0] dumpDataOut;

  wire [addrBits-1:0] unusedAddress       = {addrBits{1'bx}};
  wire                unusedReadWriteMode = `RAM_READ;
  wire [dataBits-1:0] unusedDataIn        = {dataBits{1'bx}};
  wire [dataBits-1:0] unusedDataOut;

  wire [addrBits-1:0] core0ProgramAddress;
  wire                core0ProgramReadWriteMode;
  wire [dataBits-1:0] core0ProgramDataIn;
  wire [dataBits-1:0] core0ProgramDataOut;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(romFile)) core0Program(
    .clk          (clk),
    .address      (core0ProgramAddress),
    .readWriteMode(core0ProgramReadWriteMode),
    .dataIn       (core0ProgramDataIn),
    .dataOut      (core0ProgramDataOut)
  );

  wire [addrBits-1:0] core1ProgramAddress;
  wire                core1ProgramReadWriteMode;
  wire [dataBits-1:0] core1ProgramDataIn;
  wire [dataBits-1:0] core1ProgramDataOut;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(romFile)) core1Program(
    .clk          (clk),
    .address      (core1ProgramAddress),
    .readWriteMode(core1ProgramReadWriteMode),
    .dataIn       (core1ProgramDataIn),
    .dataOut      (core1ProgramDataOut)
  );

  wire [addrBits-1:0] core0Address;
  wire                core0ReadWriteMode;
  wire [dataBits-1:0] core0DataIn;
  wire [dataBits-1:0] core0DataOut;

  wire [addrBits-1:0] core1Address;
  wire                core1ReadWriteMode;
  wire [dataBits-1:0] core1DataIn;
  wire [dataBits-1:0] core1DataOut;

  reg  [addrBits-1:0] processorInternal0Address;
  reg                 processorInternal0ReadWriteMode;
  reg  [dataBits-1:0] processorInternal0DataIn;
  wire [dataBits-1:0] processorInternal0DataOut;

  reg  [addrBits-1:0] processorInternal1Address;
  reg                 processorInternal1ReadWriteMode;
  reg  [dataBits-1:0] processorInternal1DataIn;
  wire [dataBits-1:0] processorInternal1DataOut;

  wire [2:0] cell0ToUser;
  wire [2:0] cell1ToUser;
  wire [2:0] cell2ToUser;
  wire [2:0] cell3ToUser;
  wire [2:0] cell4ToUser;
  wire [2:0] cell5ToUser;
  wire [2:0] cell6ToUser;
  wire [2:0] cell7ToUser;
  wire [2:0] cell8ToUser;
  wire [2:0] cell9ToUser;
  wire [2:0] cell10ToUser;
  wire [2:0] cell11ToUser;
  wire [2:0] cell12ToUser;
  wire [2:0] cell13ToUser;
  wire [2:0] cell14ToUser;
  wire [2:0] cell15ToUser;
  wire [2:0] cell16ToUser;

  Processor #(.addrBits(addrBits), .dataBits(dataBits)) p(
    .clk                            (clk),
    .reset                          (reset),
    .finished                       (finished),

    .core0ProgramAddress            (core0ProgramAddress),
    .core0ProgramReadWriteMode      (core0ProgramReadWriteMode),
    .core0ProgramDataIn             (core0ProgramDataIn),
    .core0ProgramDataOut            (core0ProgramDataOut),

    .core1ProgramAddress            (core1ProgramAddress),
    .core1ProgramReadWriteMode      (core1ProgramReadWriteMode),
    .core1ProgramDataIn             (core1ProgramDataIn),
    .core1ProgramDataOut            (core1ProgramDataOut),

    .core0Address                   (core0Address),
    .core0ReadWriteMode             (core0ReadWriteMode),
    .core0DataIn                    (core0DataIn),
    .core0DataOut                   (core0DataOut),

    .core1Address                   (core1Address),
    .core1ReadWriteMode             (core1ReadWriteMode),
    .core1DataIn                    (core1DataIn),
    .core1DataOut                   (core1DataOut),

    .processorInternal0Address      (processorInternal0Address),
    .processorInternal0ReadWriteMode(processorInternal0ReadWriteMode),
    .processorInternal0DataIn       (processorInternal0DataIn),
    .processorInternal0DataOut      (processorInternal0DataOut),

    .processorInternal1Address      (processorInternal1Address),
    .processorInternal1ReadWriteMode(processorInternal1ReadWriteMode),
    .processorInternal1DataIn       (processorInternal1DataIn),
    .processorInternal1DataOut      (processorInternal1DataOut),

    .cell0ToUser                    (cell0ToUser),
    .cell1ToUser                    (cell1ToUser),
    .cell2ToUser                    (cell2ToUser),
    .cell3ToUser                    (cell3ToUser),
    .cell4ToUser                    (cell4ToUser),
    .cell5ToUser                    (cell5ToUser),
    .cell6ToUser                    (cell6ToUser),
    .cell7ToUser                    (cell7ToUser),
    .cell8ToUser                    (cell8ToUser),
    .cell9ToUser                    (cell9ToUser),
    .cell10ToUser                   (cell10ToUser),
    .cell11ToUser                   (cell11ToUser),
    .cell12ToUser                   (cell12ToUser),
    .cell13ToUser                   (cell13ToUser),
    .cell14ToUser                   (cell14ToUser),
    .cell15ToUser                   (cell15ToUser),
    .cell16ToUser                   (cell16ToUser)
  );

  `define dumpRam(port) \
    begin \
      for (int i = 0; i < ramSize-1; ++i) \
        $write("%x:", port.ram[i]); \
      $write("%x\n", port.ram[ramSize-1]); \
    end;

  reg [31:0] startTime;
  reg [31:0] endTime;

  initial begin
    $dumpfile("Processor_tb.vcd");
    $dumpvars(0, Processor_tb);
    #3 reset <= 1;
    startTime <= $time;
    @(posedge finished)
      begin
        endTime = $time;
        // 2 clock cyles in iVerilog are a single actual pos edge -> pos edge
        // 2 clock cycles in hardware are actually 'one cycle' of memory time
        $display("Cycles: %0d", (endTime - startTime) / 4);
        `dumpRam(stackMemory.cell1);
        `dumpRam(stackMemory.cell2);
        `dumpRam(stackMemory.cell3);
        `dumpRam(stackMemory.cell4);
        `dumpRam(stackMemory.cell5);
        `dumpRam(stackMemory.cell6);
        `dumpRam(stackMemory.cell7);
        `dumpRam(stackMemory.cell8);
        `dumpRam(stackMemory.cell9);
        `dumpRam(stackMemory.cell10);
        `dumpRam(stackMemory.cell11);
        `dumpRam(stackMemory.cell12);
        `dumpRam(stackMemory.cell13);
        `dumpRam(stackMemory.cell14);
        `dumpRam(stackMemory.cell15);
        `dumpRam(stackMemory.cell16);
        reset <= 0;
        #4 $finish;
      end
  end
endmodule
