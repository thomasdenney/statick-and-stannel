`include "defaults.vh"
`include "opcodes.vh"
`include "status.vh"
`include "messages.vh"

module ProcessorMessageHandler #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    input  wire                enabled,
    output reg                 finished,
    // Section: core -> message. Can only handle messages from one core at once.
    input  wire [3:0]          coreMessage,
    input  wire [addrBits-1:0] coreMessageChannel,
    input  wire [dataBits-1:0] coreMessageMessage,
    input  wire [addrBits-1:0] coreMessageNumWords,
    input  wire [8:0]          coreMessageJumpDestination,
    input  wire                coreHadMessageInAlt,
    // i.e. 0 or 1
    input  wire                coreMessageSource,
    // Section: processor -> core
    // These outputs should be the direct inputs to the cores themselves
    input  wire                core0ReadyForMessage,
    input  wire                core0Executing,
    input  wire                core1ReadyForMessage,
    input  wire                core1Executing,
    output reg  [2:0]          core0ProcessorMessage,
    output reg  [dataBits-1:0] core0ProcessorMessagePushValue,
    output reg  [8:0]          core0ProcessorMessageJumpDestination,
    output reg  [2:0]          core1ProcessorMessage,
    output reg  [dataBits-1:0] core1ProcessorMessagePushValue,
    output reg  [8:0]          core1ProcessorMessageJumpDestination,
    // Section: memory. Can pass through the processor component.
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
    output wire [2:0]          cell16ToUser,
    // Used for message delivery, copying
    output reg  [addrBits-1:0] processorInternal0Address,
    output reg                 processorInternal0ReadWriteMode,
    output reg  [dataBits-1:0] processorInternal0DataIn,
    input  wire [dataBits-1:0] processorInternal0DataOut,
    // Used for copying
    output reg  [addrBits-1:0] processorInternal1Address,
    output reg                 processorInternal1ReadWriteMode,
    output reg  [dataBits-1:0] processorInternal1DataIn,
    input  wire [dataBits-1:0] processorInternal1DataOut,
    // If this is true when finished is true then the processor can halt
    output reg                 canHalt,
    output reg                 core0Active,
    output reg                 core1Active
  );

  // Section: useful values and flags
  wire [addrBits-1:0] coreMessagePid = coreMessageSource == 0 ? core0Pid : core1Pid;

  wire isProcessAllocationMessage =    coreMessage == `CORE_MESSAGE_START_PROCESS
                                    || coreMessage == `CORE_MESSAGE_HALT;
  wire isProcessSchedulingMessage =    coreMessage == `CORE_MESSAGE_YIELD;
  wire isChannelMessage           =    coreMessage == `CORE_MESSAGE_CREATE_CHANNEL
                                    || coreMessage == `CORE_MESSAGE_DELETE_CHANNEL
                                    || coreMessage == `CORE_MESSAGE_SEND
                                    || coreMessage == `CORE_MESSAGE_RECEIVE
                                    || coreMessage == `CORE_MESSAGE_ALT_START
                                    || coreMessage == `CORE_MESSAGE_ALT_WAIT
                                    || coreMessage == `CORE_MESSAGE_ALT_END
                                    || coreMessage == `CORE_MESSAGE_ENABLE_CHANNEL
                                    || coreMessage == `CORE_MESSAGE_DISABLE_CHANNEL;

  // Section: sub-components

  reg                wChannelControllerEnabled;
  reg                channelControllerFinished;
  reg                channelControllerHasChannelOut;
  reg [addrBits-1:0] channelControllerChannelOut;
  reg                channelControllerHasMessageOut;
  reg [dataBits-1:0] channelControllerMessageOut;
  reg                channelControllerHasSchedulePidOut;
  reg [addrBits-1:0] channelControllerSchedulePidOut;
  reg                channelControllerHasDeschedulePidOut;
  reg [addrBits-1:0] channelControllerDeschedulePidOut;
  // verilator lint_off UNUSED
  reg                channelControllerHasMessageInAlt;
  // verilator lint_on UNUSED

  ChannelController #(.addrBits(addrBits), .dataBits(dataBits)) cc(
    .clk                (clk),
    .reset              (reset),
    .enabled            (wChannelControllerEnabled),
    .finished           (channelControllerFinished),

    .channelOperationIn (coreMessage),
    .channelIn          (coreMessageChannel),
    .messageIn          (coreMessageMessage),
    .pidIn              (coreMessagePid),
    .rxHadMessageInAlt  (coreHadMessageInAlt),

    .hasChannelOut      (channelControllerHasChannelOut),
    .channelOut         (channelControllerChannelOut),
    .hasMessageOut      (channelControllerHasMessageOut),
    .messageOut         (channelControllerMessageOut),
    .hasSchedulePidOut  (channelControllerHasSchedulePidOut),
    .schedulePidOut     (channelControllerSchedulePidOut),
    .hasDeschedulePidOut(channelControllerHasDeschedulePidOut),
    .deschedulePidOut   (channelControllerDeschedulePidOut),
    .rxHasMessageInAlt  (channelControllerHasMessageInAlt)
  );

  reg wProcessAllocatorEnabled;
  reg processAllocatorFinished;
  wire hasProcessCreate = coreMessage == `CORE_MESSAGE_START_PROCESS;

  wire [4:0] processAllocatorTargetMemoryCell;

  reg [addrBits-1:0] processAllocatorNewPid;

  wire [dataBits-1:0] dataOutForOldStack = processorInternal0DataOut;
  wire [dataBits-1:0] dataInForOldStack;
  wire [addrBits-1:0] addressForOldStack;
  wire                readWriteForOldStack;

  // verilator lint_off UNUSED
  wire [dataBits-1:0] dataOutForNewStack = processorInternal1DataOut;
  // verilator lint_on UNUSED
  wire [dataBits-1:0] dataInForNewStack;
  wire [addrBits-1:0] addressForNewStack;
  wire                readWriteForNewStack;

  ProcessAllocator #(.addrBits(addrBits), .dataBits(dataBits)) pa(
    .clk                 (clk),
    .reset               (reset),
    .enabled             (wProcessAllocatorEnabled),
    .finished            (processAllocatorFinished),

    .hasProcessCreate    (hasProcessCreate),
    .wordsToCopy         (coreMessageNumWords),
    .startProgramCounter (coreMessageJumpDestination),
    .pidToFree           (coreMessagePid),

    .targetMemoryCell    (processAllocatorTargetMemoryCell),

    .dataOutForOldStack  (dataOutForOldStack),
    .addressForOldStack  (addressForOldStack),
    .readWriteForOldStack(readWriteForOldStack),
    .dataInForOldStack   (dataInForOldStack),
    .dataInForNewStack   (dataInForNewStack),
    .addressForNewStack  (addressForNewStack),
    .readWriteForNewStack(readWriteForNewStack),

    .newPid              (processAllocatorNewPid)
  );

  reg wSchedulerEnabled;
  reg schedulerFinished;

  reg                rHasDeschedule;
  reg [addrBits-1:0] rDeschedulePid;
  reg                rHasSchedule;
  reg [addrBits-1:0] rSchedulePid;

  reg [addrBits-1:0] core0Pid;
  reg [addrBits-1:0] core1Pid;
  reg                core0NeedsResumeAwake;
  reg                core1NeedsResumeAwake;

  reg schedulerCanHalt;

  Scheduler #(.addrBits(addrBits), .dataBits(dataBits)) scheduler(
    .clk                    (clk),
    .reset                  (reset),
    .enabled                (wSchedulerEnabled),
    .finished               (schedulerFinished),

    .core0ReadyForDeschedule(core0ReadyForMessage),
    .core1ReadyForDeschedule(core1ReadyForMessage),

    .hasDeschedule          (rHasDeschedule),
    .deschedulePid          (rDeschedulePid),
    .hasSchedule            (rHasSchedule),
    .schedulePid            (rSchedulePid),

    .core0Active            (core0Active),
    .core0Pid               (core0Pid),
    .core1Active            (core1Active),
    .core1Pid               (core1Pid),
    .core0NeedsResumeAwake  (core0NeedsResumeAwake),
    .core1NeedsResumeAwake  (core1NeedsResumeAwake),

    .canHalt                (schedulerCanHalt)
  );

  reg wMessageDeliveryEnabled;
  reg messageDeliveryFinished;

  reg [addrBits-1:0] messageDeliveryTargetPid;
  reg [dataBits-1:0] messageDeliveryMessage;
  reg                messageDeliveryNeedsJump;
  reg [8:0]          messageDeliveryJumpDestination;

  reg                 memoryCellReadWriteMode;
  reg  [addrBits-1:0] memoryCellAddress;
  reg  [dataBits-1:0] memoryCellDataIn;
  wire [dataBits-1:0] memoryCellDataOut = processorInternal0DataOut;

  reg deliverMessageToCore0;
  reg deliverMessageToCore1;

  MessageDelivery #(.addrBits(addrBits),.dataBits(dataBits)) md(
    .clk                    (clk),
    .reset                  (wMessageDeliveryEnabled),
    .finished               (messageDeliveryFinished),

    .memoryCellReadWriteMode(memoryCellReadWriteMode),
    .memoryCellAddress      (memoryCellAddress),
    .memoryCellDataIn       (memoryCellDataIn),
    .memoryCellDataOut      (memoryCellDataOut),

    .core0Process           (core0Pid),
    .core1Process           (core1Pid),

    .targetProcess          (messageDeliveryTargetPid),
    .message                (messageDeliveryMessage),
    .needsJump              (messageDeliveryNeedsJump),
    .jumpDestination        (messageDeliveryJumpDestination),
    .deliverMessageToCore0  (deliverMessageToCore0),
    .deliverMessageToCore1  (deliverMessageToCore1)
  );

  // Section: internal memory cell wiring
  assign processorInternal0Address       = wProcessAllocatorEnabled ? addressForOldStack   : memoryCellAddress;
  assign processorInternal0DataIn        = wProcessAllocatorEnabled ? dataInForOldStack    : memoryCellDataIn;
  assign processorInternal0ReadWriteMode = wProcessAllocatorEnabled ? readWriteForOldStack : memoryCellReadWriteMode;

  // This only has one user
  assign processorInternal1Address       = addressForNewStack;
  assign processorInternal1DataIn        = dataInForNewStack;
  assign processorInternal1ReadWriteMode = readWriteForNewStack;

  // Section: memory users
  // Generated by ./pmh_user_gen.py
  assign cell0ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 0 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 0 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 0 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 0 ? `USER_CORE_0 :
                                                    core1Pid                         == 0 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell1ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 1 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 1 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 1 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 1 ? `USER_CORE_0 :
                                                    core1Pid                         == 1 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell2ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 2 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 2 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 2 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 2 ? `USER_CORE_0 :
                                                    core1Pid                         == 2 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell3ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 3 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 3 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 3 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 3 ? `USER_CORE_0 :
                                                    core1Pid                         == 3 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell4ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 4 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 4 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 4 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 4 ? `USER_CORE_0 :
                                                    core1Pid                         == 4 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell5ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 5 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 5 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 5 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 5 ? `USER_CORE_0 :
                                                    core1Pid                         == 5 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell6ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 6 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 6 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 6 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 6 ? `USER_CORE_0 :
                                                    core1Pid                         == 6 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell7ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 7 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 7 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 7 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 7 ? `USER_CORE_0 :
                                                    core1Pid                         == 7 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell8ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 8 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 8 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 8 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 8 ? `USER_CORE_0 :
                                                    core1Pid                         == 8 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell9ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 9 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 9 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 9 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 9 ? `USER_CORE_0 :
                                                    core1Pid                         == 9 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell10ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 10 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 10 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 10 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 10 ? `USER_CORE_0 :
                                                    core1Pid                         == 10 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell11ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 11 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 11 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 11 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 11 ? `USER_CORE_0 :
                                                    core1Pid                         == 11 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell12ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 12 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 12 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 12 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 12 ? `USER_CORE_0 :
                                                    core1Pid                         == 12 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell13ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 13 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 13 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 13 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 13 ? `USER_CORE_0 :
                                                    core1Pid                         == 13 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell14ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 14 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 14 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 14 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 14 ? `USER_CORE_0 :
                                                    core1Pid                         == 14 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell15ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 15 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 15 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 15 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 15 ? `USER_CORE_0 :
                                                    core1Pid                         == 15 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;
  assign cell16ToUser = wProcessAllocatorEnabled && coreMessagePid                   == 16 ? `USER_PROCESSOR_0 :
                        wProcessAllocatorEnabled && processAllocatorTargetMemoryCell == 16 ? `USER_PROCESSOR_1 :
                        wMessageDeliveryEnabled  && messageDeliveryTargetPid         == 16 ? `USER_PROCESSOR_0 :
                                                    core0Pid                         == 16 ? `USER_CORE_0 :
                                                    core1Pid                         == 16 ? `USER_CORE_1 :
                                                                                             `USER_UNUSED;

  // State
  reg [2:0] rState;
  reg       rHasMessageDelivery;

  reg [2:0]          rFinalCore0ProcessorMessage;
  reg [dataBits-1:0] rFinalCore0ProcessorMessagePushValue;
  reg [8:0]          rFinalCore0ProcessorMessageJumpDestination;

  reg [2:0]          rFinalCore1ProcessorMessage;
  reg [dataBits-1:0] rFinalCore1ProcessorMessagePushValue;
  reg [8:0]          rFinalCore1ProcessorMessageJumpDestination;

  reg rAwaitCore0;
  reg rAwaitCore1;

  localparam STATE_INIT               = 3'd0;
  localparam STATE_PROCESS_ALLOCATOR  = 3'd1;
  localparam STATE_CHANNEL_CONTROLLER = 3'd2;
  localparam STATE_SCHEDULER          = 3'd3;
  localparam STATE_SCHEDULER_WAIT     = 3'd4;
  localparam STATE_MESSAGE_DELIVERY   = 3'd5;
  localparam STATE_DONE               = 3'd6;

  // Signals
  reg [2:0] wNextState;
  reg       wFinished;

  reg                wSchedule;
  reg [addrBits-1:0] wSchedulePid;

  reg                wDeschedule;
  reg [addrBits-1:0] wDeschedulePid;


  reg                wUpdateFinalCore0ProcessorMessage;
  reg [2:0]          wFinalCore0ProcessorMessage;
  reg [dataBits-1:0] wFinalCore0ProcessorMessagePushValue;
  reg [8:0]          wFinalCore0ProcessorMessageJumpDestination;

  reg                wUpdateFinalCore1ProcessorMessage;
  reg [2:0]          wFinalCore1ProcessorMessage;
  reg [dataBits-1:0] wFinalCore1ProcessorMessagePushValue;
  reg [8:0]          wFinalCore1ProcessorMessageJumpDestination;

  reg                wHasMessage;
  reg [dataBits-1:0] wMessageToDeliver;
  reg [addrBits-1:0] wTargetPid;
  reg                wNeedsJump;

  reg wAwaitCore0;
  reg wAwaitCore1;

  // Sequential logic
  always @(posedge clk)
    begin
      if (!reset)
        begin
          finished <= 0;
          canHalt  <= 1;
        end
      else if (enabled)
        begin
          if (wSchedule)
            begin
              rHasSchedule <= 1;
              rSchedulePid <= wSchedulePid;
            end

          if (wDeschedule)
            begin
              rHasDeschedule <= 1;
              rDeschedulePid <= wDeschedulePid;
            end

          if (wUpdateFinalCore0ProcessorMessage)
            begin
              rFinalCore0ProcessorMessage                <= wFinalCore0ProcessorMessage;
              rFinalCore0ProcessorMessagePushValue       <= wFinalCore0ProcessorMessagePushValue;
              rFinalCore0ProcessorMessageJumpDestination <= wFinalCore0ProcessorMessageJumpDestination;
            end

          if (wUpdateFinalCore1ProcessorMessage)
            begin
              rFinalCore1ProcessorMessage                <= wFinalCore1ProcessorMessage;
              rFinalCore1ProcessorMessagePushValue       <= wFinalCore1ProcessorMessagePushValue;
              rFinalCore1ProcessorMessageJumpDestination <= wFinalCore1ProcessorMessageJumpDestination;
            end

          if (wHasMessage)
            begin
              rHasMessageDelivery             <= 1;
              messageDeliveryTargetPid       <= wTargetPid;
              messageDeliveryMessage         <= wMessageToDeliver;
              messageDeliveryNeedsJump       <= wNeedsJump;
              messageDeliveryJumpDestination <= coreMessageJumpDestination;
            end

          rAwaitCore0 <= wAwaitCore0;
          rAwaitCore1 <= wAwaitCore1;

          canHalt  <= schedulerCanHalt;
          rState   <= wNextState;
          finished <= wFinished;
        end
      else
        begin
          rState              <= 0;
          finished            <= 0;
          rHasSchedule        <= 0;
          rHasDeschedule      <= 0;
          rHasMessageDelivery <= 0;
          rAwaitCore0         <= 0;
          rAwaitCore1         <= 0;
          rFinalCore0ProcessorMessage <= `PROCESSOR_MESSAGE_NONE;
          rFinalCore1ProcessorMessage <= `PROCESSOR_MESSAGE_NONE;
        end
    end

  // Combinatorial logic
  always @(*)
    begin
      wChannelControllerEnabled            = 0;
      wProcessAllocatorEnabled             = 0;
      wSchedulerEnabled                    = 0;
      wMessageDeliveryEnabled              = 0;
      wNextState                           = rState;
      wFinished                            = 0;
      wSchedule                            = 0;
      wDeschedule                          = 0;
      wSchedulePid                         = {addrBits{1'bx}};
      wDeschedulePid                       = {addrBits{1'bx}};
      wHasMessage                          = 0;
      wMessageToDeliver                    = {dataBits{1'bx}};
      wTargetPid                           = {addrBits{1'bx}};
      wNeedsJump                           = 0;
      core0ProcessorMessage                = `PROCESSOR_MESSAGE_NONE;
      core0ProcessorMessagePushValue       = {dataBits{1'bx}};
      core0ProcessorMessageJumpDestination = 9'bx;
      core1ProcessorMessage                = `PROCESSOR_MESSAGE_NONE;
      core1ProcessorMessagePushValue       = {dataBits{1'bx}};
      core1ProcessorMessageJumpDestination = 9'bx;

      wUpdateFinalCore0ProcessorMessage          = 0;
      wFinalCore0ProcessorMessage                = `PROCESSOR_MESSAGE_NONE;
      wFinalCore0ProcessorMessagePushValue       = {dataBits{1'bx}};
      wFinalCore0ProcessorMessageJumpDestination = 9'bx;

      wUpdateFinalCore1ProcessorMessage          = 0;
      wFinalCore1ProcessorMessage                = `PROCESSOR_MESSAGE_NONE;
      wFinalCore1ProcessorMessagePushValue       = {dataBits{1'bx}};
      wFinalCore1ProcessorMessageJumpDestination = 9'bx;

      wAwaitCore0 = 0;
      wAwaitCore1 = 1;

      case (rState)
        STATE_INIT:
          begin
            if (enabled)
              begin
                if (isProcessAllocationMessage)
                  begin
                    // Can't advance any earlier because the core must complete
                    // write back before either creating a process based on the
                    // current stack or deallocating the memory cell.
                    if ((coreMessageSource == 0 && core0ReadyForMessage) ||
                        (coreMessageSource == 1 && core1ReadyForMessage))
                      begin
                        // This can be enabled immediately because all of the inputs of
                        // the process allocator are wire from this module's inputs.
                        wProcessAllocatorEnabled = 1;
                        wNextState               = STATE_PROCESS_ALLOCATOR;
                        if (coreMessageSource == 0)
                          begin
                            wUpdateFinalCore0ProcessorMessage = coreMessagePid != 0;
                            wFinalCore0ProcessorMessage       = `PROCESSOR_MESSAGE_RESUME;
                          end
                        else
                          begin
                            wUpdateFinalCore1ProcessorMessage = coreMessagePid != 0;
                            wFinalCore1ProcessorMessage       = `PROCESSOR_MESSAGE_RESUME;
                          end
                      end
                  end
                else if (isProcessSchedulingMessage) // i.e. yield
                  begin
                    wNextState     = STATE_SCHEDULER;
                    wSchedule      = 1;
                    wDeschedule    = 1;
                    wSchedulePid   = coreMessagePid;
                    wDeschedulePid = coreMessagePid;
                  end
                else if (isChannelMessage)
                  begin
                    // As above, we can start this immediately
                    wChannelControllerEnabled = 1;
                    wNextState = STATE_CHANNEL_CONTROLLER;
                    if (coreMessage == `CORE_MESSAGE_ENABLE_CHANNEL || coreMessage == `CORE_MESSAGE_DISABLE_CHANNEL)
                      begin
                        if (coreMessageSource == 0)
                          begin
                            wUpdateFinalCore0ProcessorMessage = coreMessagePid != 0;
                            wFinalCore0ProcessorMessage       = `PROCESSOR_MESSAGE_RESUME;
                          end
                        else
                          begin
                            wUpdateFinalCore1ProcessorMessage = coreMessagePid != 0;
                            wFinalCore1ProcessorMessage       = `PROCESSOR_MESSAGE_RESUME;
                          end
                      end
                  end
              end
          end
        STATE_PROCESS_ALLOCATOR:
          begin
            wProcessAllocatorEnabled = ~processAllocatorFinished;
            if (processAllocatorFinished)
              begin
                wNextState = STATE_SCHEDULER;
                if (hasProcessCreate)
                  begin
                    wSchedule    = 1;
                    wSchedulePid = processAllocatorNewPid;
                  end
                else
                  begin
                    wDeschedule    = 1;
                    wDeschedulePid = coreMessagePid;
                  end
              end
          end
        STATE_CHANNEL_CONTROLLER:
          begin
            wChannelControllerEnabled = ~channelControllerFinished;
            if (channelControllerFinished)
              begin
                if (channelControllerHasChannelOut)
                  begin
                    wNextState = STATE_DONE;
                    if (coreMessageSource == 0)
                      begin
                        wUpdateFinalCore0ProcessorMessage    = 1;
                        wFinalCore0ProcessorMessage          = `PROCESSOR_MESSAGE_RECEIVE;
                        wFinalCore0ProcessorMessagePushValue = { 8'b0, channelControllerChannelOut };
                      end
                    else
                      begin
                        wUpdateFinalCore1ProcessorMessage    = 1;
                        wFinalCore1ProcessorMessage          = `PROCESSOR_MESSAGE_RECEIVE;
                        wFinalCore1ProcessorMessagePushValue = { 8'b0, channelControllerChannelOut };
                      end
                  end
                else
                  begin
                    if (coreMessage == `CORE_MESSAGE_DELETE_CHANNEL
                         || coreMessage == `CORE_MESSAGE_ALT_START
                         || coreMessage == `CORE_MESSAGE_ALT_END
                         || (coreMessage == `CORE_MESSAGE_ALT_WAIT && ~channelControllerHasDeschedulePidOut)
                         || (coreMessage == `CORE_MESSAGE_SEND && ~channelControllerHasDeschedulePidOut)
                         || (coreMessage == `CORE_MESSAGE_RECEIVE && ~channelControllerHasDeschedulePidOut)
                         )
                      begin
                        if (coreMessage != `CORE_MESSAGE_SEND && coreMessage != `CORE_MESSAGE_RECEIVE)
                          wNextState = STATE_DONE;
                        if (coreMessageSource == 0)
                          begin
                            wUpdateFinalCore0ProcessorMessage = 1;
                            wFinalCore0ProcessorMessage = `PROCESSOR_MESSAGE_RESUME;
                          end
                        else
                          begin
                            wUpdateFinalCore1ProcessorMessage = 1;
                            wFinalCore1ProcessorMessage = `PROCESSOR_MESSAGE_RESUME;
                          end
                      end
                    wSchedule = channelControllerHasSchedulePidOut;
                    wSchedulePid = channelControllerSchedulePidOut;
                    wDeschedule = channelControllerHasDeschedulePidOut;
                    wDeschedulePid = channelControllerDeschedulePidOut;
                    wHasMessage = channelControllerHasMessageOut;
                    if (wHasMessage)
                      begin
                        wMessageToDeliver = channelControllerMessageOut;
                        wNeedsJump = coreMessage == `CORE_MESSAGE_DISABLE_CHANNEL;
                        wTargetPid = coreMessage == `CORE_MESSAGE_RECEIVE || coreMessage == `CORE_MESSAGE_DISABLE_CHANNEL ? coreMessagePid : wSchedulePid;
                      end
                    wNextState = wSchedule || wDeschedule ? STATE_SCHEDULER :
                                 wHasMessage              ? STATE_MESSAGE_DELIVERY : STATE_DONE;
                  end
              end
          end
        STATE_SCHEDULER:
          begin
            wSchedulerEnabled = ~schedulerFinished;
            if (schedulerFinished)
              begin
                wNextState = rHasMessageDelivery ? STATE_MESSAGE_DELIVERY : STATE_DONE;
                if (core0NeedsResumeAwake)
                  begin
                    if (!core0ReadyForMessage)
                      wNextState = STATE_MESSAGE_DELIVERY;
                    wAwaitCore0 = 1;
                    core0ProcessorMessage = `PROCESSOR_MESSAGE_RESUME_AND_WAIT;
                    wUpdateFinalCore0ProcessorMessage = 1;
                    wFinalCore0ProcessorMessage = `PROCESSOR_MESSAGE_RESUME;
                  end
                if (core1NeedsResumeAwake)
                  begin
                    if (!core1ReadyForMessage)
                      wNextState = STATE_MESSAGE_DELIVERY;
                    wAwaitCore1 = 1;
                    core1ProcessorMessage = `PROCESSOR_MESSAGE_RESUME_AND_WAIT;
                    wUpdateFinalCore1ProcessorMessage = 1;
                    wFinalCore1ProcessorMessage = `PROCESSOR_MESSAGE_RESUME;
                  end
              end
          end
        STATE_SCHEDULER_WAIT:
          begin
            if (rAwaitCore0)
              begin
                wAwaitCore0 = ~core0ReadyForMessage;
                core0ProcessorMessage = `PROCESSOR_MESSAGE_RESUME_AND_WAIT;
              end
            if (rAwaitCore1)
              begin
                wAwaitCore1 = ~core1ReadyForMessage;
                core1ProcessorMessage = `PROCESSOR_MESSAGE_RESUME_AND_WAIT;
              end
            if (!wAwaitCore0 && !wAwaitCore1)
              wNextState = rHasMessageDelivery ? STATE_MESSAGE_DELIVERY : STATE_DONE;
          end
        STATE_MESSAGE_DELIVERY:
          begin
            wMessageDeliveryEnabled = ~messageDeliveryFinished;
            if (messageDeliveryFinished)
              begin
                wNextState = STATE_DONE;
                if (deliverMessageToCore0)
                  begin
                    wUpdateFinalCore0ProcessorMessage          = 1;
                    wFinalCore0ProcessorMessage                = messageDeliveryNeedsJump ? `PROCESSOR_MESSAGE_RECEIVE_AND_JUMP_AND_WAIT : `PROCESSOR_MESSAGE_RECEIVE;
                    wFinalCore0ProcessorMessagePushValue       = messageDeliveryMessage;
                    wFinalCore0ProcessorMessageJumpDestination = messageDeliveryJumpDestination;
                  end
                if (deliverMessageToCore1)
                  begin
                    wUpdateFinalCore1ProcessorMessage          = 1;
                    wFinalCore1ProcessorMessage                = messageDeliveryNeedsJump ? `PROCESSOR_MESSAGE_RECEIVE_AND_JUMP_AND_WAIT : `PROCESSOR_MESSAGE_RECEIVE;
                    wFinalCore1ProcessorMessagePushValue       = messageDeliveryMessage;
                    wFinalCore1ProcessorMessageJumpDestination = messageDeliveryJumpDestination;
                  end
              end
          end
        STATE_DONE:
          begin
            if (core0Active)
              core0ProcessorMessage = rFinalCore0ProcessorMessage;

            core0ProcessorMessagePushValue       = rFinalCore0ProcessorMessagePushValue;
            core0ProcessorMessageJumpDestination = rFinalCore0ProcessorMessageJumpDestination;

            if (core1Active)
              core1ProcessorMessage = rFinalCore1ProcessorMessage;

            core1ProcessorMessagePushValue       = rFinalCore1ProcessorMessagePushValue;
            core1ProcessorMessageJumpDestination = rFinalCore1ProcessorMessageJumpDestination;

            // NOTE: I am not 100% certain this is the correct way to finish
            wFinished = (core0ReadyForMessage || core0Executing) && (core1ReadyForMessage || core1Executing);
          end
        default:
          begin
          end
      endcase
    end

endmodule
