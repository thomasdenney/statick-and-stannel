`include "defaults.vh"

module Processor #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    input  wire clk,
    input  wire reset,
    output wire finished,

    output wire [addrBits-1:0] core0ProgramAddress,
    output wire                core0ProgramReadWriteMode,
    output wire [dataBits-1:0] core0ProgramDataIn,
    input  wire [dataBits-1:0] core0ProgramDataOut,

    output wire [addrBits-1:0] core1ProgramAddress,
    output wire                core1ProgramReadWriteMode,
    output wire [dataBits-1:0] core1ProgramDataIn,
    input  wire [dataBits-1:0] core1ProgramDataOut,

    output wire [addrBits-1:0] core0Address,
    output wire                core0ReadWriteMode,
    output wire [dataBits-1:0] core0DataIn,
    input  wire [dataBits-1:0] core0DataOut,

    output wire [addrBits-1:0] core1Address,
    output wire                core1ReadWriteMode,
    output wire [dataBits-1:0] core1DataIn,
    input  wire [dataBits-1:0] core1DataOut,

    output reg  [addrBits-1:0] processorInternal0Address,
    output reg                 processorInternal0ReadWriteMode,
    output reg  [dataBits-1:0] processorInternal0DataIn,
    input  wire [dataBits-1:0] processorInternal0DataOut,

    output reg  [addrBits-1:0] processorInternal1Address,
    output reg                 processorInternal1ReadWriteMode,
    output reg  [dataBits-1:0] processorInternal1DataIn,
    input  wire [dataBits-1:0] processorInternal1DataOut,

    output wire [2:0]          cell0ToUser,
    output wire [2:0]          cell1ToUser,
    output wire [2:0]          cell2ToUser,
    output wire [2:0]          cell3ToUser,
    output wire [2:0]          cell4ToUser,
    output wire [2:0]          cell5ToUser,
    output wire [2:0]          cell6ToUser,
    output wire [2:0]          cell7ToUser,
    output wire [2:0]          cell8ToUser,
    output wire [2:0]          cell9ToUser,
    output wire [2:0]          cell10ToUser,
    output wire [2:0]          cell11ToUser,
    output wire [2:0]          cell12ToUser,
    output wire [2:0]          cell13ToUser,
    output wire [2:0]          cell14ToUser,
    output wire [2:0]          cell15ToUser,
    output wire [2:0]          cell16ToUser
  );

  assign core0ProgramReadWriteMode = `RAM_READ;
  assign core0ProgramDataIn        = {dataBits{1'bx}};

  assign core1ProgramReadWriteMode = `RAM_READ;
  assign core1ProgramDataIn        = {dataBits{1'bx}};

  // Subcomponents

  reg  [2:0]          core0ProcessorMessage;
  reg  [dataBits-1:0] core0ProcessorMessagePushValue;
  reg  [8:0]          core0ProcessorMessageJumpDestination;

  reg  [3:0]          core0Message;
  reg  [addrBits-1:0] core0MessageChannel;
  reg  [dataBits-1:0] core0MessageMessage;
  reg  [addrBits-1:0] core0MessageNumWords;
  reg  [8:0]          core0MessageJumpDestination;
  reg                 core0HadMessageInAlt;

  reg core0ReadyForMessage;
  reg core0Executing;

  Core #(.addrBits(addrBits), .dataBits(dataBits), .cpuId(0)) core0(
    .clk                            (clk),
    .reset                          (reset),
    .programAddress                 (core0ProgramAddress),
    .programDataOut                 (core0ProgramDataOut),
    .ramDataOut                     (core0DataOut),
    .ramReadWriteMode               (core0ReadWriteMode),
    .ramDataIn                      (core0DataIn),
    .ramAddress                     (core0Address),
    .processorMessage               (core0ProcessorMessage),
    .processorMessagePushValue      (core0ProcessorMessagePushValue),
    .processorMessageJumpDestination(core0ProcessorMessageJumpDestination),
    .coreMessage                    (core0Message),
    .coreMessageChannel             (core0MessageChannel),
    .coreMessageMessage             (core0MessageMessage),
    .coreMessageNumWords            (core0MessageNumWords),
    .coreMessageJumpDestination     (core0MessageJumpDestination),
    .coreHadMessageInAlt            (core0HadMessageInAlt),
    .executing                      (core0Executing),
    .readyToReceive                 (core0ReadyForMessage)
  );

  reg  [2:0]          core1ProcessorMessage;
  reg  [dataBits-1:0] core1ProcessorMessagePushValue;
  reg  [8:0]          core1ProcessorMessageJumpDestination;

  reg  [3:0]          core1Message;
  reg  [addrBits-1:0] core1MessageChannel;
  reg  [dataBits-1:0] core1MessageMessage;
  reg  [addrBits-1:0] core1MessageNumWords;
  reg  [8:0]          core1MessageJumpDestination;

  reg core1Executing;
  reg core1ReadyForMessage;
  reg core1HadMessageInAlt;

  Core #(.addrBits(addrBits), .dataBits(dataBits), .cpuId(1)) core1(
    .clk                            (clk),
    .reset                          (reset),
    .programAddress                 (core1ProgramAddress),
    .programDataOut                 (core1ProgramDataOut),
    .ramDataOut                     (core1DataOut),
    .ramReadWriteMode               (core1ReadWriteMode),
    .ramDataIn                      (core1DataIn),
    .ramAddress                     (core1Address),
    .processorMessage               (core1ProcessorMessage),
    .processorMessagePushValue      (core1ProcessorMessagePushValue),
    .processorMessageJumpDestination(core1ProcessorMessageJumpDestination),
    .coreMessage                    (core1Message),
    .coreMessageChannel             (core1MessageChannel),
    .coreMessageMessage             (core1MessageMessage),
    .coreMessageNumWords            (core1MessageNumWords),
    .coreMessageJumpDestination     (core1MessageJumpDestination),
    .coreHadMessageInAlt            (core1HadMessageInAlt),
    .executing                      (core1Executing),
    .readyToReceive                 (core1ReadyForMessage)
  );

  reg processorMessageHandlerFinished;
  reg canHalt;
  reg core0Active;
  reg core1Active;

  ProcessorMessageHandler #(.addrBits(addrBits), .dataBits(dataBits)) pmh(
    // Section: operational I/Os
    .clk(clk),
    .reset(reset),
    .enabled(wProcessorMessageHandlerEnabled),
    .finished(processorMessageHandlerFinished),
    // Section: core -> message. Can only handle messages from one core at once.
    .coreMessage(rCoreMessage),
    .coreMessageChannel(rCoreMessageChannel),
    .coreMessageMessage(rCoreMessageMessage),
    .coreMessageNumWords(rCoreMessageNumWords),
    .coreMessageJumpDestination(rCoreMessageJumpDestination),
    .coreHadMessageInAlt(rCoreHadMessageInAlt),

    .coreMessageSource(rCoreMessageSource),

    .core0ReadyForMessage(core0ReadyForMessage),
    .core0Executing(core0Executing),
    .core1ReadyForMessage(core1ReadyForMessage),
    .core1Executing(core1Executing),
    .core0ProcessorMessage(core0ProcessorMessage),
    .core0ProcessorMessagePushValue(core0ProcessorMessagePushValue),
    .core0ProcessorMessageJumpDestination(core0ProcessorMessageJumpDestination),
    .core1ProcessorMessage(core1ProcessorMessage),
    .core1ProcessorMessagePushValue(core1ProcessorMessagePushValue),
    .core1ProcessorMessageJumpDestination(core1ProcessorMessageJumpDestination),

    .cell0ToUser(cell0ToUser),
    .cell1ToUser(cell1ToUser),
    .cell2ToUser(cell2ToUser),
    .cell3ToUser(cell3ToUser),
    .cell4ToUser(cell4ToUser),
    .cell5ToUser(cell5ToUser),
    .cell6ToUser(cell6ToUser),
    .cell7ToUser(cell7ToUser),
    .cell8ToUser(cell8ToUser),
    .cell9ToUser(cell9ToUser),
    .cell10ToUser(cell10ToUser),
    .cell11ToUser(cell11ToUser),
    .cell12ToUser(cell12ToUser),
    .cell13ToUser(cell13ToUser),
    .cell14ToUser(cell14ToUser),
    .cell15ToUser(cell15ToUser),
    .cell16ToUser(cell16ToUser),

    .processorInternal0Address(processorInternal0Address),
    .processorInternal0ReadWriteMode(processorInternal0ReadWriteMode),
    .processorInternal0DataIn(processorInternal0DataIn),
    .processorInternal0DataOut(processorInternal0DataOut),

    .processorInternal1Address(processorInternal1Address),
    .processorInternal1ReadWriteMode(processorInternal1ReadWriteMode),
    .processorInternal1DataIn(processorInternal1DataIn),
    .processorInternal1DataOut(processorInternal1DataOut),

    .canHalt(canHalt),
    .core0Active(core0Active),
    .core1Active(core1Active)
  );

  // State
  reg [1:0] rState;
  reg rFinished;

  reg rCorePriority;

  reg [3:0]          rCoreMessage;
  reg [addrBits-1:0] rCoreMessageChannel;
  reg [dataBits-1:0] rCoreMessageMessage;
  reg [addrBits-1:0] rCoreMessageNumWords;
  reg [8:0]          rCoreMessageJumpDestination;
  reg                rCoreMessageSource;
  reg                rCoreHadMessageInAlt;

  assign finished = rFinished;

  localparam STATE_INIT                 = 2'd0;
  localparam STATE_SETUP_FIRST_PROCESS  = 2'd1;
  localparam STATE_HANDLE_MESSAGE       = 2'd2;
  localparam STATE_EXECUTE              = 2'd3;

  // Signals
  reg [1:0] wNextState;
  reg wFinished;

  reg                wUpdateCoreMessage;
  reg [3:0]          wCoreMessage;
  reg [addrBits-1:0] wCoreMessageChannel;
  reg [dataBits-1:0] wCoreMessageMessage;
  reg [addrBits-1:0] wCoreMessageNumWords;
  reg [8:0]          wCoreMessageJumpDestination;
  reg                wCoreHadMessageInAlt;
  reg                wCoreMessageSource;
  reg                wProcessorMessageHandlerEnabled;

  always @(posedge clk)
    begin
      if (!reset)
        begin
          rFinished     <= 0;
          rState        <= 0;
          rCorePriority <= 0;
        end
      else
        begin
          if (rState == STATE_HANDLE_MESSAGE && wNextState == STATE_EXECUTE)
            rCorePriority <= ~rCorePriority;

          if (wUpdateCoreMessage)
            begin
              rCoreMessage                <= wCoreMessage;
              rCoreMessageChannel         <= wCoreMessageChannel;
              rCoreMessageMessage         <= wCoreMessageMessage;
              rCoreMessageNumWords        <= wCoreMessageNumWords;
              rCoreMessageJumpDestination <= wCoreMessageJumpDestination;
              rCoreHadMessageInAlt        <= wCoreHadMessageInAlt;
              rCoreMessageSource          <= wCoreMessageSource;
            end

          rState    <= wNextState;
          rFinished <= wFinished;
        end
    end

  always @(*)
  begin
    wNextState  = rState;
    wFinished   = 0;
    wProcessorMessageHandlerEnabled = 0;

    wUpdateCoreMessage          = 0;
    wCoreMessage                = `CORE_MESSAGE_NONE;
    wCoreMessageChannel         = {addrBits{1'bx}};
    wCoreMessageMessage         = {dataBits{1'bx}};
    wCoreMessageNumWords        = {addrBits{1'bx}};
    wCoreMessageJumpDestination = 9'bx;
    wCoreHadMessageInAlt        = 1'bx;
    wCoreMessageSource          = 1'bx;

    case (rState)
      STATE_INIT:
        wNextState = STATE_SETUP_FIRST_PROCESS;
      STATE_SETUP_FIRST_PROCESS:
        begin
          wUpdateCoreMessage = 1;
          wCoreMessage = `CORE_MESSAGE_START_PROCESS;
          wCoreMessageNumWords = 0;
          wCoreMessageJumpDestination = 0;
          wCoreMessageSource = 1;
          wNextState = STATE_HANDLE_MESSAGE;
        end
      STATE_HANDLE_MESSAGE:
        begin
          wProcessorMessageHandlerEnabled = ~processorMessageHandlerFinished;
          if (processorMessageHandlerFinished)
            begin
              if (canHalt)
                wFinished = 1;
              wNextState = STATE_EXECUTE;
            end
        end
      STATE_EXECUTE:
        begin
          wFinished = canHalt;
          if (rCorePriority == 0)
            begin
              if (core0Message != `CORE_MESSAGE_NONE && core0Active)
                begin
                  wUpdateCoreMessage          = 1;
                  wCoreMessage                = core0Message;
                  wCoreMessageNumWords        = core0MessageNumWords;
                  wCoreMessageJumpDestination = core0MessageJumpDestination;
                  wCoreMessageChannel         = core0MessageChannel;
                  wCoreMessageMessage         = core0MessageMessage;
                  wCoreHadMessageInAlt        = core0HadMessageInAlt;
                  wCoreMessageSource          = 0;
                  wNextState                  = STATE_HANDLE_MESSAGE;
                end
              else if (core1Message != `CORE_MESSAGE_NONE && core1Active)
                begin
                  wUpdateCoreMessage          = 1;
                  wCoreMessage                = core1Message;
                  wCoreMessageNumWords        = core1MessageNumWords;
                  wCoreMessageJumpDestination = core1MessageJumpDestination;
                  wCoreMessageChannel         = core1MessageChannel;
                  wCoreMessageMessage         = core1MessageMessage;
                  wCoreHadMessageInAlt        = core1HadMessageInAlt;
                  wCoreMessageSource          = 1;
                  wNextState                  = STATE_HANDLE_MESSAGE;
                end
            end
          else
            begin
              if (core1Message != `CORE_MESSAGE_NONE && core1Active)
                begin
                  wUpdateCoreMessage          = 1;
                  wCoreMessage                = core1Message;
                  wCoreMessageNumWords        = core1MessageNumWords;
                  wCoreMessageJumpDestination = core1MessageJumpDestination;
                  wCoreMessageChannel         = core1MessageChannel;
                  wCoreMessageMessage         = core1MessageMessage;
                  wCoreHadMessageInAlt        = core1HadMessageInAlt;
                  wCoreMessageSource          = 1;
                  wNextState                  = STATE_HANDLE_MESSAGE;
                end
              else if (core0Message != `CORE_MESSAGE_NONE && core0Active)
                begin
                  wUpdateCoreMessage          = 1;
                  wCoreMessage                = core0Message;
                  wCoreMessageNumWords        = core0MessageNumWords;
                  wCoreMessageJumpDestination = core0MessageJumpDestination;
                  wCoreMessageChannel         = core0MessageChannel;
                  wCoreMessageMessage         = core0MessageMessage;
                  wCoreHadMessageInAlt        = core0HadMessageInAlt;
                  wCoreMessageSource          = 0;
                  wNextState                  = STATE_HANDLE_MESSAGE;
                end
            end
        end
      default:
        begin end
    endcase
  end

endmodule
