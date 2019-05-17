`include "defaults.vh"

module SoC #(parameter clockRate = `ICE_STICK_CLOCK_RATE) (
    input wire clk,
    input wire rx,
    output wire tx,
    output wire [2:0] status
  );

  parameter addrBits = `ADDRESS_BITS;
  parameter dataBits = `DATA_BITS;

  // Initialisation
  reg reset = 0;

  localparam STATE_LOAD             = 0;
  localparam STATE_RUN              = 1;
  localparam STATE_DUMP_RAM_CORE_1  = 2;
  localparam STATE_DUMP_RAM_CORE_2  = 3;
  localparam STATE_DUMP_RAM_CORE_3  = 4;
  localparam STATE_DUMP_RAM_CORE_4  = 5;
  localparam STATE_DUMP_RAM_CORE_5  = 6;
  localparam STATE_DUMP_RAM_CORE_6  = 7;
  localparam STATE_DUMP_RAM_CORE_7  = 8;
  localparam STATE_DUMP_RAM_CORE_8  = 9;
  localparam STATE_DUMP_RAM_CORE_9  = 10;
  localparam STATE_DUMP_RAM_CORE_10 = 11;
  localparam STATE_DUMP_RAM_CORE_11 = 12;
  localparam STATE_DUMP_RAM_CORE_12 = 13;
  localparam STATE_DUMP_RAM_CORE_13 = 14;
  localparam STATE_DUMP_RAM_CORE_14 = 15;
  localparam STATE_DUMP_RAM_CORE_15 = 16;
  localparam STATE_DUMP_RAM_CORE_16 = 17;

  reg [4:0] state;
  reg [4:0] wNextState;

  wire isLoad           = state == STATE_LOAD;
  wire isProcessor      = state == STATE_RUN;
  wire isDumpRam        = !isLoad && !isProcessor;

  wire [addrBits-1:0] uartAddress;
  wire                uartReadWriteMode;
  wire [dataBits-1:0] uartDataIn;
  // verilator lint_off UNUSED
  wire [dataBits-1:0] uartDataOut;
  // verilator lint_on UNUSED

  wire [addrBits-1:0] core0ProgramAddress;
  wire                core0ProgramReadWriteMode;
  wire [dataBits-1:0] core0ProgramDataIn;
  wire [dataBits-1:0] core0ProgramDataOut;

  wire [addrBits-1:0] core1ProgramAddress;
  wire                core1ProgramReadWriteMode;
  wire [dataBits-1:0] core1ProgramDataIn;
  wire [dataBits-1:0] core1ProgramDataOut;

  MemoryController2x3 #(.addrBits(addrBits), .dataBits(dataBits)) instructionMemory(
    .address0(core0ProgramAddress),
    .address1(core1ProgramAddress),
    .address2(uartAddress),
    .readWriteMode0(core0ProgramReadWriteMode),
    .readWriteMode1(core1ProgramReadWriteMode),
    .readWriteMode2(uartReadWriteMode),
    .dataIn0(core0ProgramDataIn),
    .dataIn1(core1ProgramDataIn),
    .dataIn2(uartDataIn),
    .dataOut0(core0ProgramDataOut),
    .dataOut1(core1ProgramDataOut),
    .dataOut2(uartDataOut),
    .cell0ToUser(isLoad ? 2'd2 : 2'd0),
    .cell1ToUser(isLoad ? 2'd2 : 2'd1),
    .clk(clk)
  );

  wire [addrBits-1:0] core0Address;
  wire                core0ReadWriteMode;
  wire [dataBits-1:0] core0DataIn;
  wire [dataBits-1:0] core0DataOut;

  wire [addrBits-1:0] core1Address;
  wire                core1ReadWriteMode;
  wire [dataBits-1:0] core1DataIn;
  wire [dataBits-1:0] core1DataOut;

  wire [addrBits-1:0] dumpAddress;
  wire                dumpReadWriteMode;
  wire [dataBits-1:0] dumpDataIn;
  wire [dataBits-1:0] dumpDataOut;

  wire dumpFinished;

  RamDumper #(.addrBits(addrBits), .dataBits(dataBits), .clockRate(clockRate)) ramDumper0(
    .clk(clk),
    .reset(reset),
    .enabled(isDumpRam),
    .dataIn(dumpDataIn),
    .readWriteMode(dumpReadWriteMode),
    .dataOut(dumpDataOut),
    .address(dumpAddress),
    .txReady(txReady),
    .txSignalStart(dumpTxSignalStart),
    .txData(dumpTxData),
    .finished(dumpFinished)
  );

  wire [addrBits-1:0] unusedAddress       = {addrBits{1'bx}};
  wire                unusedReadWriteMode = `RAM_READ;
  wire [dataBits-1:0] unusedDataIn        = {dataBits{1'bx}};
  wire [dataBits-1:0] unusedDataOut;

  reg [2:0] wCell0User = `USER_UNUSED;
  reg [2:0] wCell1User;
  reg [2:0] wCell2User;
  reg [2:0] wCell3User;
  reg [2:0] wCell4User;
  reg [2:0] wCell5User;
  reg [2:0] wCell6User;
  reg [2:0] wCell7User;
  reg [2:0] wCell8User;
  reg [2:0] wCell9User;
  reg [2:0] wCell10User;
  reg [2:0] wCell11User;
  reg [2:0] wCell12User;
  reg [2:0] wCell13User;
  reg [2:0] wCell14User;
  reg [2:0] wCell15User;
  reg [2:0] wCell16User;

  wire [2:0] cell0User  = state == STATE_RUN ? processorCell0ToUser : wCell0User;
  wire [2:0] cell1User  = state == STATE_RUN ? processorCell1ToUser : wCell1User;
  wire [2:0] cell2User  = state == STATE_RUN ? processorCell2ToUser : wCell2User;
  wire [2:0] cell3User  = state == STATE_RUN ? processorCell3ToUser : wCell3User;
  wire [2:0] cell4User  = state == STATE_RUN ? processorCell4ToUser : wCell4User;
  wire [2:0] cell5User  = state == STATE_RUN ? processorCell5ToUser : wCell5User;
  wire [2:0] cell6User  = state == STATE_RUN ? processorCell6ToUser : wCell6User;
  wire [2:0] cell7User  = state == STATE_RUN ? processorCell7ToUser : wCell7User;
  wire [2:0] cell8User  = state == STATE_RUN ? processorCell8ToUser : wCell8User;
  wire [2:0] cell9User  = state == STATE_RUN ? processorCell9ToUser : wCell9User;
  wire [2:0] cell10User = state == STATE_RUN ? processorCell10ToUser : wCell10User;
  wire [2:0] cell11User = state == STATE_RUN ? processorCell11ToUser : wCell11User;
  wire [2:0] cell12User = state == STATE_RUN ? processorCell12ToUser : wCell12User;
  wire [2:0] cell13User = state == STATE_RUN ? processorCell13ToUser : wCell13User;
  wire [2:0] cell14User = state == STATE_RUN ? processorCell14ToUser : wCell14User;
  wire [2:0] cell15User = state == STATE_RUN ? processorCell15ToUser : wCell15User;
  wire [2:0] cell16User = state == STATE_RUN ? processorCell16ToUser : wCell16User;

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
    .cell0ToUser   (cell0User),
    .cell1ToUser   (cell1User),
    .cell2ToUser   (cell2User),
    .cell3ToUser   (cell3User),
    .cell4ToUser   (cell4User),
    .cell5ToUser   (cell5User),
    .cell6ToUser   (cell6User),
    .cell7ToUser   (cell7User),
    .cell8ToUser   (cell8User),
    .cell9ToUser   (cell9User),
    .cell10ToUser  (cell10User),
    .cell11ToUser  (cell11User),
    .cell12ToUser  (cell12User),
    .cell13ToUser  (cell13User),
    .cell14ToUser  (cell14User),
    .cell15ToUser  (cell15User),
    .cell16ToUser  (cell16User)
  );

  wire [2:0] processorCell0ToUser;
  wire [2:0] processorCell1ToUser;
  wire [2:0] processorCell2ToUser;
  wire [2:0] processorCell3ToUser;
  wire [2:0] processorCell4ToUser;
  wire [2:0] processorCell5ToUser;
  wire [2:0] processorCell6ToUser;
  wire [2:0] processorCell7ToUser;
  wire [2:0] processorCell8ToUser;
  wire [2:0] processorCell9ToUser;
  wire [2:0] processorCell10ToUser;
  wire [2:0] processorCell11ToUser;
  wire [2:0] processorCell12ToUser;
  wire [2:0] processorCell13ToUser;
  wire [2:0] processorCell14ToUser;
  wire [2:0] processorCell15ToUser;
  wire [2:0] processorCell16ToUser;

  assign status = state[2:0];

  reg  [addrBits-1:0] processorInternal0Address;
  reg                 processorInternal0ReadWriteMode;
  reg  [dataBits-1:0] processorInternal0DataIn;
  wire [dataBits-1:0] processorInternal0DataOut;

  reg  [addrBits-1:0] processorInternal1Address;
  reg                 processorInternal1ReadWriteMode;
  reg  [dataBits-1:0] processorInternal1DataIn;
  wire [dataBits-1:0] processorInternal1DataOut;

  wire processorFinished;

  Processor #(.addrBits(addrBits), .dataBits(dataBits)) processor(
    .clk                          (clk),
    .reset                        (isProcessor),
    .finished                     (processorFinished),

    .core0ProgramAddress          (core0ProgramAddress),
    .core0ProgramReadWriteMode    (core0ProgramReadWriteMode),
    .core0ProgramDataIn           (core0ProgramDataIn),
    .core0ProgramDataOut          (core0ProgramDataOut),

    .core1ProgramAddress          (core1ProgramAddress),
    .core1ProgramReadWriteMode    (core1ProgramReadWriteMode),
    .core1ProgramDataIn           (core1ProgramDataIn),
    .core1ProgramDataOut          (core1ProgramDataOut),

    .core0Address                 (core0Address),
    .core0ReadWriteMode           (core0ReadWriteMode),
    .core0DataIn                  (core0DataIn),
    .core0DataOut                 (core0DataOut),

    .core1Address                 (core1Address),
    .core1ReadWriteMode           (core1ReadWriteMode),
    .core1DataIn                  (core1DataIn),
    .core1DataOut                 (core1DataOut),

    .processorInternal0Address       (processorInternal0Address),
    .processorInternal0ReadWriteMode (processorInternal0ReadWriteMode),
    .processorInternal0DataIn        (processorInternal0DataIn),
    .processorInternal0DataOut       (processorInternal0DataOut),

    .processorInternal1Address       (processorInternal1Address),
    .processorInternal1ReadWriteMode (processorInternal1ReadWriteMode),
    .processorInternal1DataIn        (processorInternal1DataIn),
    .processorInternal1DataOut       (processorInternal1DataOut),

    .cell0ToUser                  (processorCell0ToUser),
    .cell1ToUser                  (processorCell1ToUser),
    .cell2ToUser                  (processorCell2ToUser),
    .cell3ToUser                  (processorCell3ToUser),
    .cell4ToUser                  (processorCell4ToUser),
    .cell5ToUser                  (processorCell5ToUser),
    .cell6ToUser                  (processorCell6ToUser),
    .cell7ToUser                  (processorCell7ToUser),
    .cell8ToUser                  (processorCell8ToUser),
    .cell9ToUser                  (processorCell9ToUser),
    .cell10ToUser                 (processorCell10ToUser),
    .cell11ToUser                 (processorCell11ToUser),
    .cell12ToUser                 (processorCell12ToUser),
    .cell13ToUser                 (processorCell13ToUser),
    .cell14ToUser                 (processorCell14ToUser),
    .cell15ToUser                 (processorCell15ToUser),
    .cell16ToUser                 (processorCell16ToUser)
  );

  wire uartStart = isLoad;

  wire [7:0] dumpTxData;
  wire       dumpTxSignalStart;

  wire [7:0] txData        = dumpTxData;
  wire       txReady;
  wire       txSignalStart = dumpTxSignalStart;

  UartTx #(.clockRate(clockRate)) txComponent(
    .clk(clk),
    .reset(reset),
    .start(txSignalStart),
    .data(txData),
    .tx(tx),
    .ready(txReady)
  );

  wire loadFinished;

  Loader #(.addrBits(addrBits), .dataBits(dataBits), .clockRate(clockRate)) loader0(
    .clk(clk),
    .reset(reset),
    .rx(rx),
    .enabled(uartStart),
    .dataIn(uartDataIn),
    .address(uartAddress),
    .readWriteMode(uartReadWriteMode),
    .finishedReading(loadFinished)
  );

  always @(posedge clk)
    begin
        if (!reset)
        state <= STATE_LOAD;
      else
        state <= wNextState;
      reset <= 1;
    end

  always @(*)
  begin
    wNextState = dumpFinished ? state + 1 : state;
    wCell0User = `USER_UNUSED;
    wCell1User = `USER_UNUSED;
    wCell2User = `USER_UNUSED;
    wCell3User = `USER_UNUSED;
    wCell4User = `USER_UNUSED;
    wCell5User = `USER_UNUSED;
    wCell6User = `USER_UNUSED;
    wCell7User = `USER_UNUSED;
    wCell8User = `USER_UNUSED;
    wCell9User = `USER_UNUSED;
    wCell10User = `USER_UNUSED;
    wCell11User = `USER_UNUSED;
    wCell12User = `USER_UNUSED;
    wCell13User = `USER_UNUSED;
    wCell14User = `USER_UNUSED;
    wCell15User = `USER_UNUSED;
    wCell16User = `USER_UNUSED;
    case (state)
      STATE_LOAD:
        wNextState = loadFinished  ? state + 1 : state;
      STATE_RUN:
        wNextState = processorFinished ? state + 1 : state;
      STATE_DUMP_RAM_CORE_1:
        wCell1User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_2:
        wCell2User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_3:
        wCell3User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_4:
        wCell4User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_5:
        wCell5User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_6:
        wCell6User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_7:
        wCell7User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_8:
        wCell8User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_9:
        wCell9User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_10:
        wCell10User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_11:
        wCell11User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_12:
        wCell12User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_13:
        wCell13User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_14:
        wCell14User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_15:
        wCell15User = `USER_CORE_DUMPER;
      STATE_DUMP_RAM_CORE_16:
        begin
          wCell16User = `USER_CORE_DUMPER;
          wNextState = dumpFinished ? STATE_LOAD : state;
        end
    endcase
  end

endmodule
