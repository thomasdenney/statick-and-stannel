`include "defaults.vh"
`include "messages.vh"

module ProcessorMessageHandler_tb();
  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  // Clock
  reg clk;
  always #1 clk = clk !== 1'b1;

  // Test component
  reg                reset = 0;
  reg                enabled;
  reg                finished;

  reg [3:0]          coreMessage;
  reg [addrBits-1:0] coreMessageChannel;
  reg [dataBits-1:0] coreMessageMessage;
  reg [addrBits-1:0] coreMessageNumWords;
  reg [8:0]          coreMessageJumpDestination;
  reg                coreHadMessageInAlt = 0;

  reg                coreMessageSource;

  reg                core0ReadyForMessage = 1;
  reg                core0Executing = 1;
  reg                core1ReadyForMessage = 1;
  reg                core1Executing = 1;

  reg [2:0]          core0ProcessorMessage;
  reg [dataBits-1:0] core0ProcessorMessagePushValue;
  reg [8:0]          core0ProcessorMessageJumpDestination;
  reg [2:0]          core1ProcessorMessage;
  reg [dataBits-1:0] core1ProcessorMessagePushValue;
  reg [8:0]          core1ProcessorMessageJumpDestination;

  reg [2:0]          cell0ToUser;
  reg [2:0]          cell1ToUser;
  reg [2:0]          cell2ToUser;
  reg [2:0]          cell3ToUser;
  reg [2:0]          cell4ToUser;
  reg [2:0]          cell5ToUser;
  reg [2:0]          cell6ToUser;
  reg [2:0]          cell7ToUser;
  reg [2:0]          cell8ToUser;
  reg [2:0]          cell9ToUser;
  reg [2:0]          cell10ToUser;
  reg [2:0]          cell11ToUser;
  reg [2:0]          cell12ToUser;
  reg [2:0]          cell13ToUser;
  reg [2:0]          cell14ToUser;
  reg [2:0]          cell15ToUser;
  reg [2:0]          cell16ToUser;

  reg  [addrBits-1:0] processorInternal0Address;
  reg                 processorInternal0ReadWriteMode;
  reg  [dataBits-1:0] processorInternal0DataIn;
  reg  [dataBits-1:0] processorInternal0DataOut;

  reg  [addrBits-1:0] processorInternal1Address;
  reg                 processorInternal1ReadWriteMode;
  reg  [dataBits-1:0] processorInternal1DataIn;
  reg  [dataBits-1:0] processorInternal1DataOut;

  reg                 canHalt;
  reg                 core0Active;
  reg                 core1Active;

  ProcessorMessageHandler #(.addrBits(addrBits), .dataBits(dataBits)) pmh(
    .clk                                 (clk),
    .reset                               (reset),
    .enabled                             (enabled),
    .finished                            (finished),

    .coreMessage                         (coreMessage),
    .coreMessageChannel                  (coreMessageChannel),
    .coreMessageMessage                  (coreMessageMessage),
    .coreMessageNumWords                 (coreMessageNumWords),
    .coreMessageJumpDestination          (coreMessageJumpDestination),
    .coreHadMessageInAlt                 (coreHadMessageInAlt),

    .coreMessageSource                   (coreMessageSource),

    .core0ReadyForMessage                (core0ReadyForMessage),
    .core0Executing                      (core0Executing),
    .core1ReadyForMessage                (core1ReadyForMessage),
    .core1Executing                      (core1Executing),
    .core0ProcessorMessage               (core0ProcessorMessage),
    .core0ProcessorMessagePushValue      (core0ProcessorMessagePushValue),
    .core0ProcessorMessageJumpDestination(core0ProcessorMessageJumpDestination),
    .core1ProcessorMessage               (core1ProcessorMessage),
    .core1ProcessorMessagePushValue      (core1ProcessorMessagePushValue),
    .core1ProcessorMessageJumpDestination(core1ProcessorMessageJumpDestination),

    .cell0ToUser                         (cell0ToUser),
    .cell1ToUser                         (cell1ToUser),
    .cell2ToUser                         (cell2ToUser),
    .cell3ToUser                         (cell3ToUser),
    .cell4ToUser                         (cell4ToUser),
    .cell5ToUser                         (cell5ToUser),
    .cell6ToUser                         (cell6ToUser),
    .cell7ToUser                         (cell7ToUser),
    .cell8ToUser                         (cell8ToUser),
    .cell9ToUser                         (cell9ToUser),
    .cell10ToUser                        (cell10ToUser),
    .cell11ToUser                        (cell11ToUser),
    .cell12ToUser                        (cell12ToUser),
    .cell13ToUser                        (cell13ToUser),
    .cell14ToUser                        (cell14ToUser),
    .cell15ToUser                        (cell15ToUser),
    .cell16ToUser                        (cell16ToUser),

    .processorInternal0Address           (processorInternal0Address),
    .processorInternal0ReadWriteMode     (processorInternal0ReadWriteMode),
    .processorInternal0DataIn            (processorInternal0DataIn),
    .processorInternal0DataOut           (processorInternal0DataOut),

    .processorInternal1Address           (processorInternal1Address),
    .processorInternal1ReadWriteMode     (processorInternal1ReadWriteMode),
    .processorInternal1DataIn            (processorInternal1DataIn),
    .processorInternal1DataOut           (processorInternal1DataOut),

    .canHalt                             (canHalt),
    .core0Active                         (core0Active),
    .core1Active                         (core1Active)
  );

  // Memory controller
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

  wire [addrBits-1:0] unusedAddress       = {addrBits{1'bx}};
  wire                unusedReadWriteMode = `RAM_READ;
  wire [dataBits-1:0] unusedDataIn        = {dataBits{1'bx}};
  wire [dataBits-1:0] unusedDataOut;

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

  // Tests
  task initialStateCanHaltTest;
    begin
      if (canHalt !== 1'b1) $error("Should be able to halt in the initial state");
    end
  endtask

  reg createProcess1TestHasResumed = 0;
  task createProcess1Test;
    begin
      enabled                    <= 1;
      coreMessage                <= `CORE_MESSAGE_START_PROCESS;
      coreMessageNumWords        <= 0;
      coreMessageJumpDestination <= 0;
      coreMessageSource          <= 0;
      @(core0ProcessorMessage)
        begin
          if (core0ProcessorMessage != `PROCESSOR_MESSAGE_RESUME_AND_WAIT) $error("Expected to receive resume and wait");
          if (pmh.core0Pid != 1) $error("expected to be allocated PID 1 to core 0");
          // I couldn't find a better way of checking resumed processes
          createProcess1TestHasResumed <= 1;
        end
      @(core0ProcessorMessage)
        begin
          if (createProcess1TestHasResumed)
            if (core0ProcessorMessage != `PROCESSOR_MESSAGE_RESUME) $error("Expected signal of resume, not %0d", core0ProcessorMessage);
        end
      @(posedge finished)
        begin
          enabled <= 0;
          if (pmh.core0Pid != 1) $error("Expected core 0 to be on pid 1");
          if (!pmh.core0Active) $error("Expected core 0 to be active");
          if (pmh.core1Active) $error("Core 1 should not be active");
          if (canHalt) $error("Shouldn't be able to halt");
        end
    end
  endtask

  task yieldProcess1Test;
    begin
      coreMessage       <= `CORE_MESSAGE_YIELD;
      coreMessageSource <= 0;
      enabled           <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (pmh.core0Pid != 1) $error("After yielding, pid 1 should be immediately reschedule");
          if (!pmh.core0Active) $error("Core 0 should be active");
          if (pmh.core1Active) $error("Core 1 should not be active");
        end
    end
  endtask

  task createProcess2Test;
    enabled     <= 1;
    coreMessage <= `CORE_MESSAGE_START_PROCESS;
    @(core1ProcessorMessage)
        begin
          if (core1ProcessorMessage != `PROCESSOR_MESSAGE_RESUME_AND_WAIT) $error("Expected to receive resume and wait");
          if (pmh.core1Pid != 2) $error("expected to be allocated PID 2 to core 1");
        end
    @(core0ProcessorMessage)
      begin
        if (core0ProcessorMessage != `PROCESSOR_MESSAGE_RESUME) $error("Only expected to receive resume on core 0");
        if (core1ProcessorMessage != `PROCESSOR_MESSAGE_RESUME) $error("Expected signal of resume for core 1 at the same time");
      end
    @(posedge finished)
      begin
        enabled <= 0;
        if (!pmh.core0Active) $error("Core 0 should be active");
        if (pmh.core0Pid !== 1) $error("Core 0 should be assigned PID 1");
        if (!pmh.core1Active) $error("Core 1 should be active");
        if (pmh.core1Pid !== 2) $error("Core 1 should be assigned PID 2");
      end
  endtask

  task process1CreateChannel0Test;
    begin
      enabled           <= 1;
      coreMessageSource <= 0;
      coreMessage       <= `CORE_MESSAGE_CREATE_CHANNEL;
      @(posedge finished)
        begin
          enabled <= 0;
          if (core0ProcessorMessage != `PROCESSOR_MESSAGE_RECEIVE) $error("Core 0 expected receive message");
          if (core0ProcessorMessagePushValue != 0) $error("Expected to receive newly allocated push value 0");
        end
    end
  endtask

  task process1DeleteChannel0Test;
    begin
      enabled            <= 1;
      coreMessageSource  <= 0;
      coreMessage        <= `CORE_MESSAGE_DELETE_CHANNEL;
      coreMessageChannel <= 0;
      // Deliberate delay
      core0ReadyForMessage <= 0;
      #10 core0ReadyForMessage <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (core0ProcessorMessage != `PROCESSOR_MESSAGE_RESUME) $error("Core 0 expected resume message");
        end
    end
  endtask

  task process1CreateChannel2Test;
    begin
      enabled           <= 1;
      coreMessageSource <= 0;
      coreMessage       <= `CORE_MESSAGE_CREATE_CHANNEL;
      @(posedge finished)
        begin
          enabled <= 0;
          if (core0ProcessorMessage != `PROCESSOR_MESSAGE_RECEIVE) $error("Core 0 expected receive message");
          if (core0ProcessorMessagePushValue != 2) $error("Expected to receive newly allocated push value 2");
        end
    end
  endtask

  task process1SendMessageToChannel2Test;
    begin
      enabled            <= 1;
      coreMessageSource  <= 0;
      coreMessage        <= `CORE_MESSAGE_SEND;
      coreMessageChannel <= 2;
      coreMessageMessage <= 42;
      @(posedge finished)
        begin
          enabled <= 0;
          if (pmh.core0Active) $error("Core 0 should not be active after sending a message to a channel without listeners");
          if (!pmh.core1Active) $error("Core 1 should be active");
          if (pmh.core1Pid != 2) $error("Core 1 should still have pid 2");
        end
    end
  endtask

  task process2ReceiveMessageFromChannel2Test;
    begin
      enabled            <= 1;
      coreMessageSource  <= 1;
      coreMessage        <= `CORE_MESSAGE_RECEIVE;
      coreMessageChannel <= 2;
      @(posedge finished)
        begin
          enabled <= 0;
          if (!pmh.core0Active) $error("Core 0 should be active after receiving a message");
          if (pmh.core0Pid != 1) $error("Core 0 should still have pid 0");
          if (!pmh.core1Active) $error("Core 1 should be active");
          if (pmh.core1Pid != 2) $error("Core 1 should still have pid 2");
          if (core0ProcessorMessage != `PROCESSOR_MESSAGE_RESUME) $error("Core 0 should resume");
          if (core1ProcessorMessage != `PROCESSOR_MESSAGE_RECEIVE) $error("Core 1 should receive");
          if (core1ProcessorMessagePushValue != 42) $error("Should receive 42");
        end
    end
  endtask

  task haltProcess1Test;
    begin
      enabled           <= 1;
      coreMessage       <= `CORE_MESSAGE_HALT;
      coreMessageSource <= 0;
      @(posedge finished)
        begin
          enabled <= 0;
          if (pmh.core0Active) $error("Core 0 should not be active");
          if (!pmh.core1Active) $error("Core 1 should have remained active");
          if (pmh.canHalt) $error("Shouldn't be able to halt");
        end
    end
  endtask

  task haltProcess2Test;
    begin
      enabled           <= 1;
      coreMessage       <= `CORE_MESSAGE_HALT;
      coreMessageSource <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (pmh.core0Active) $error("Core 0 should not be active");
          if (pmh.core1Active) $error("Core 1 should not be active");
          if (!pmh.canHalt) $error("Should be able to halt");
        end
    end
  endtask

  initial begin
    $dumpfile("ProcessorMessageHandler_tb.vcd");
    $dumpvars(0, ProcessorMessageHandler_tb);

    #2 reset <= 1;
    // Tests in this file are separated by 2 cycles (4 ticks) to ensure that the
    // PMH has the opportunity to reset internal state.
    #4 initialStateCanHaltTest;
    #4 createProcess1Test;
    #4 yieldProcess1Test;
    #4 createProcess2Test;
    #4 process1CreateChannel0Test;
    #4 process1DeleteChannel0Test;
    #4 process1CreateChannel2Test;
    #4 process1SendMessageToChannel2Test;
    #4 process2ReceiveMessageFromChannel2Test;
    #4 haltProcess1Test;
    #4 haltProcess2Test;
    #2 $finish;
  end
endmodule
