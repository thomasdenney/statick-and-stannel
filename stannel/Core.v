`include "defaults.vh"
`include "opcodes.vh"
`include "status.vh"

module Core #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS, parameter cpuId = 0) (
    input  wire                clk,
    input  wire                reset,
    input  wire [dataBits-1:0] ramDataOut,
    output wire                ramReadWriteMode,
    output wire [dataBits-1:0] ramDataIn,
    output wire [addrBits-1:0] ramAddress,
    input wire  [dataBits-1:0] programDataOut,
    output wire [addrBits-1:0] programAddress,
    // Communication from Processor
    input  wire [2:0]          processorMessage,
    input  wire [dataBits-1:0] processorMessagePushValue,
    input  wire [8:0]          processorMessageJumpDestination,
    // Communication to Processor
    output reg                 readyToReceive,
    output reg                 executing,
    output reg  [3:0]          coreMessage,
    output reg  [addrBits-1:0] coreMessageChannel,
    output reg  [dataBits-1:0] coreMessageMessage,
    output reg  [addrBits-1:0] coreMessageNumWords,
    output reg  [8:0]          coreMessageJumpDestination,
    output reg                 coreHadMessageInAlt
  );

  // SECTION: Memory controller

  localparam ComponentIDFetch   = 3'b000;
  localparam ComponentIDExecute = 3'b001;
  localparam ComponentIDIO      = 3'b010;
  localparam ComponentIDSave    = 3'b011;
  localparam ComponentIDResume  = 3'b100;
  localparam ComponentIDNone    = 3'b101;

  wire [addrBits-1:0] fetchStackAddress;
  wire                fetchStackReadWriteMode = `RAM_READ;
  wire [dataBits-1:0] fetchDataIn = {dataBits{1'bx}};

  wire [dataBits-1:0] execDataIn;
  wire [addrBits-1:0] execAddress;
  wire                execReadWriteMode;

  wire [dataBits-1:0] ioDataIn;
  wire [addrBits-1:0] ioAddress;
  wire                ioReadWriteMode;

  wire [dataBits-1:0] saveStateDataIn;
  wire [addrBits-1:0] saveStateAddress;
  wire                saveStateReadWriteMode;

  wire [dataBits-1:0] resumeStateDataIn = {dataBits{1'bx}};
  wire [addrBits-1:0] resumeStateAddress;
  wire                resumeStateReadWriteMode;

  wire [dataBits-1:0] noDataIn        = {dataBits{1'bx}};
  wire [addrBits-1:0] noAddress       = {addrBits{1'bx}};
  wire                noReadWriteMode = `RAM_READ;

  reg [2:0] componentWithMemoryControl = ComponentIDNone;

  MemoryControllerExternal6 #(.addrBits(addrBits), .dataBits(dataBits)) memMultiplexer(
    .address0      (fetchStackAddress),
    .readWriteMode0(fetchStackReadWriteMode),
    .dataIn0       (fetchDataIn),

    .address1      (execAddress),
    .readWriteMode1(execReadWriteMode),
    .dataIn1       (execDataIn),

    .address2      (ioAddress),
    .readWriteMode2(ioReadWriteMode),
    .dataIn2       (ioDataIn),

    .address3      (saveStateAddress),
    .readWriteMode3(saveStateReadWriteMode),
    .dataIn3       (saveStateDataIn),

    .address4      (resumeStateAddress),
    .readWriteMode4(resumeStateReadWriteMode),
    .dataIn4       (resumeStateDataIn),

    .address5      (noAddress),
    .readWriteMode5(noReadWriteMode),
    .dataIn5       (noDataIn),

    .cellToUser    (componentWithMemoryControl),
    .address       (ramAddress),
    .dataIn        (ramDataIn),
    .readWriteMode (ramReadWriteMode)
  );

  // SECTION: State

  localparam STATE_FETCH_STACK       = 0;
  localparam STATE_FETCH_INSTRUCTION = 1;
  localparam STATE_EXECUTE           = 2;
  localparam STATE_IO                = 3;
  localparam STATE_PUSH_NEXT_LOWER   = 4;
  localparam STATE_PUSH_NEXT_UPPER   = 5;
  localparam STATE_SAVE              = 6;
  localparam STATE_RESUME            = 8;
  localparam STATE_SAVE_AWAIT        = 9;
  localparam STATE_AWAIT             = 10;
  localparam STATE_RESUME_WAIT       = 11;

  reg stackPushFinished = 0;

  reg [3:0] state;
  reg [3:0] nextState;

  // SECTION: Actual "main" registers

  reg [8:0]          programCounter;
  reg [addrBits-1:0] stackPointer;
  reg [addrBits-1:0] callStackPointer;

  reg [dataBits-1:0] topOfStack1;
  reg [dataBits-1:0] topOfStack2;
  reg [dataBits-1:0] topOfStack3;

  // SECTION: Submodules

  // SUBSECTION: Stack fetch

  wire  fetchStackFinished;
  reg   wFetchStackEnabled;

  wire [dataBits-1:0] fetchedTopOfStack1;
  wire [dataBits-1:0] fetchedTopOfStack2;
  wire [dataBits-1:0] fetchedTopOfStack3;

  FetchStack #(.addrBits(addrBits), .dataBits(dataBits)) fetch0(
    .clk(clk),
    .reset(wFetchStackEnabled),
    .dataOut(ramDataOut),
    .address(fetchStackAddress),
    .finished(fetchStackFinished),
    .stackPointer(stackPointer),
    .topOfStack1(fetchedTopOfStack1),
    .topOfStack2(fetchedTopOfStack2),
    .topOfStack3(fetchedTopOfStack3)
  );

  // SUBSECTION: Instruction fetch

  reg  wFetchInstructionEnabled;
  reg fetchInstructionUseInternalProgramCounter;
  wire fetchInstructionFinished;
  wire [7:0] fetchedInstruction;
  wire [8:0] fetchedNextProgramCounter;

  FetchInstruction #(.addrBits(addrBits), .dataBits(dataBits)) fetchInstruction0(
    .clk(clk),
    .reset(wFetchInstructionEnabled),
    .useInternalProgramCounter(fetchInstructionUseInternalProgramCounter),
    .programCounter(programCounter),
    .programAddress(programAddress),
    .programDataOut(programDataOut),
    .finished(fetchInstructionFinished),
    .instruction(fetchedInstruction),
    .nextProgramCounter(fetchedNextProgramCounter)
  );

  // SUBSECTION: Resume state

  wire resumeStateEnabled = state == STATE_RESUME || state == STATE_RESUME_WAIT;
  wire resumeStateFinished;

  wire [addrBits-1:0] resumeStateStackPointer;
  wire [addrBits-1:0] resumeStateCallStackPointer;
  wire [8:0]          resumeStateProgramCounter;
  wire [3:0]          resumeStateAluFlags;

  ResumeState #(.addrBits(addrBits), .dataBits(dataBits)) resumeState0(
    .clk             (clk),
    .reset           (resumeStateEnabled),
    .address         (resumeStateAddress),
    .rwMode          (resumeStateReadWriteMode),
    .finished        (resumeStateFinished),
    .dataOut         (ramDataOut),
    .stackPointer    (resumeStateStackPointer),
    .callStackPointer(resumeStateCallStackPointer),
    .programCounter  (resumeStateProgramCounter),
    .aluFlags        (resumeStateAluFlags)
  );

  // SUBSECTION: Execute

  wire executeEnabled = state == STATE_EXECUTE;
  wire executeReset = reset;

  wire [8:0]          executeNextProgramCounter;
  wire [addrBits-1:0] executeNextStackPointer;
  wire [addrBits-1:0] executeNextCallStackPointer;
  wire [dataBits-1:0] executeNextTopOfStack1;
  wire [dataBits-1:0] executeNextTopOfStack2;
  wire [dataBits-1:0] executeNextTopOfStack3;

  wire       executeUseOutputOfRAM;
  wire [2:0] executeDestinationRegisterOfRamOutput;
  wire [1:0] executeStatus;
  wire       executeFinished;
  wire       executePushNextLower;
  wire       executePushNextUpper;
  wire       executeProgramCounterIsIncremented;
  wire [3:0] exportedAluFlags;

  wire                executeIoEnabled0;
  wire [addrBits-1:0] executeIoAddress0;
  wire                executeIoReadWriteMode0;
  wire [dataBits-1:0] executeIoWriteValue0;
  wire [2:0]          executeIoReadRegister0;
  wire                executeNeedsFullFetch;

  reg [addrBits-1:0] rExecuteIoAddress0;
  reg                rExecuteIoReadWriteMode0;
  reg [dataBits-1:0] rExecuteIoWriteValue0;
  reg [2:0]          rExecuteIoReadRegister0;

  reg  [3:0]          executeMessage;
  reg  [addrBits-1:0] executeMessageChannel;
  reg  [dataBits-1:0] executeMessageMessage;
  reg  [addrBits-1:0] executeMessageNumWords;
  reg  [8:0]          executeMessageJumpDestination;

  wire loadFlagsFromSavedState = state == STATE_RESUME;

  Execute #(.addrBits(addrBits), .dataBits(dataBits), .cpuId(cpuId)) execute0(
    .clk(clk),
    .enabled(executeEnabled),
    .reset(executeReset),
    .finished(executeFinished),
    .addr(execAddress),
    .dataIn(execDataIn),
    .ramRW(execReadWriteMode),
    .expectedNextProgramCounter(fetchedNextProgramCounter),
    .stackPointer(stackPointer),
    .callStackPointer(callStackPointer),
    .instruction(fetchedInstruction),
    .topOfStack1(topOfStack1),
    .topOfStack2(topOfStack2),
    .topOfStack3(topOfStack3),
    .nextProgramCounter(executeNextProgramCounter),
    .nextStackPointer(executeNextStackPointer),
    .nextCallStackPointer(executeNextCallStackPointer),
    .nextTopOfStack1(executeNextTopOfStack1),
    .nextTopOfStack2(executeNextTopOfStack2),
    .nextTopOfStack3(executeNextTopOfStack3),
    .nextTopOfStackOnAlt(rNewTopOfStackOnAltEnd),
    .nextPCOnAlt(rPCOnAltEnd),
    .useOutputOfRAM(executeUseOutputOfRAM),
    .destinationRegisterOfRamOutput(executeDestinationRegisterOfRamOutput),
    .pushNextLower(executePushNextLower),
    .pushNextUpper(executePushNextUpper),
    .programCounterIsIncremented(executeProgramCounterIsIncremented),
    .status(executeStatus),
    .ioEnabled0(executeIoEnabled0),
    .ioAddress0(executeIoAddress0),
    .ioReadWriteMode0(executeIoReadWriteMode0),
    .ioWriteValue0(executeIoWriteValue0),
    .ioReadRegister0(executeIoReadRegister0),
    .needsFullFetch(executeNeedsFullFetch),
    .exportedAluFlags(exportedAluFlags),
    .loadFlagsFromSavedState(loadFlagsFromSavedState),
    .savedFlags(resumeStateAluFlags),
    .message(executeMessage),
    .messageChannel(executeMessageChannel),
    .messageMessage(executeMessageMessage),
    .messageNumWords(executeMessageNumWords),
    .messageJumpDestination(executeMessageJumpDestination)
  );

  // SUBSECTION: IO

  wire ioReset = state == STATE_IO;
  wire ioFinished;

  wire [8:0]          ioNextProgramCounter;
  wire [addrBits-1:0] ioNextStackPointer;
  wire [addrBits-1:0] ioNextCallStackPointer;
  wire [dataBits-1:0] ioNextTopOfStack1;
  wire [dataBits-1:0] ioNextTopOfStack2;
  wire [dataBits-1:0] ioNextTopOfStack3;

  Io #(.addrBits(addrBits), .dataBits(dataBits)) io0(
    .clk(clk),
    .reset(ioReset),
    .finished(ioFinished),
    .dataOut(ramDataOut),
    .addr(ioAddress),
    .dataIn(ioDataIn),
    .ramRW(ioReadWriteMode),
    .programCounter(programCounter),
    .stackPointer(stackPointer),
    .callStackPointer(callStackPointer),
    .topOfStack1(topOfStack1),
    .topOfStack2(topOfStack2),
    .topOfStack3(topOfStack3),
    .nextProgramCounter(ioNextProgramCounter),
    .nextStackPointer(ioNextStackPointer),
    .nextCallStackPointer(ioNextCallStackPointer),
    .nextTopOfStack1(ioNextTopOfStack1),
    .nextTopOfStack2(ioNextTopOfStack2),
    .nextTopOfStack3(ioNextTopOfStack3),
    .readWriteAction(rExecuteIoReadWriteMode0),
    .readOrWriteAddress(rExecuteIoAddress0),
    .writeValue(rExecuteIoWriteValue0),
    .destinationRegister(rExecuteIoReadRegister0)
  );


  wire saveStateEnabled = state == STATE_SAVE || state == STATE_SAVE_AWAIT;
  wire saveStateFinished;

  // SUBSECTION: Save state
  SaveState #(.addrBits(addrBits), .dataBits(dataBits)) saveState0(
    .clk(clk),
    .reset(saveStateEnabled),
    .finished(saveStateFinished),
    .address(saveStateAddress),
    .dataIn(saveStateDataIn),
    .rwMode(saveStateReadWriteMode),
    .programCounter(programCounter),
    .stackPointer(stackPointer),
    .callStackPointer(callStackPointer),
    .topOfStack1(topOfStack1),
    .topOfStack2(topOfStack2),
    .topOfStack3(topOfStack3),
    .aluFlags(exportedAluFlags)
  );

  reg wUpdateCoreMessage;
  reg wClearCoreMessage;

  reg rNeedsSaveAwait;
  reg wUpdateNeedsSaveAwait;
  reg wNextNeedsSaveAwait;
  reg wDisableFetchInternalPC;

  reg                wUpdatePCAndTopOfStack;
  reg [8:0]          wNewPC;
  reg [dataBits-1:0] wNewTopOfStack;

  reg [8:0]          rPCOnAltEnd;
  reg [dataBits-1:0] rNewTopOfStackOnAltEnd;

  reg [8:0]          wPCOnAltEnd;
  reg [dataBits-1:0] wNewTopOfStackOnAltEnd;
  reg                wCoreHadMessageInAlt;

  always @(posedge clk)
    begin
      if (state == STATE_FETCH_STACK && fetchStackFinished)
        begin
          topOfStack1 <= fetchedTopOfStack1;
          topOfStack2 <= fetchedTopOfStack2;
          topOfStack3 <= fetchedTopOfStack3;
          fetchInstructionUseInternalProgramCounter <= 0;
        end
      else if (state == STATE_FETCH_INSTRUCTION && fetchInstructionFinished)
        fetchInstructionUseInternalProgramCounter <= 1; // Reset to default
      else if (resumeStateEnabled && resumeStateFinished)
        begin
          programCounter   <= resumeStateProgramCounter;
          callStackPointer <= resumeStateCallStackPointer;
          stackPointer     <= resumeStateStackPointer;
        end
      else if (state == STATE_EXECUTE && executeFinished)
        begin
          programCounter   <= executeUseOutputOfRAM && executeDestinationRegisterOfRamOutput == `REG_PC  ? ramDataOut[8:0] : executeNextProgramCounter;
          stackPointer     <= executeUseOutputOfRAM && executeDestinationRegisterOfRamOutput == `REG_SP  ? ramDataOut[addrBits-1:0] : executeNextStackPointer;
          callStackPointer <= executeUseOutputOfRAM && executeDestinationRegisterOfRamOutput == `REG_CSP ? ramDataOut[addrBits-1:0] : executeNextCallStackPointer;
          topOfStack1      <= executeUseOutputOfRAM && executeDestinationRegisterOfRamOutput == `REG_S1  ? ramDataOut : executeNextTopOfStack1;
          topOfStack2      <= executeUseOutputOfRAM && executeDestinationRegisterOfRamOutput == `REG_S2  ? ramDataOut : executeNextTopOfStack2;
          topOfStack3      <= executeUseOutputOfRAM && executeDestinationRegisterOfRamOutput == `REG_S3  ? ramDataOut : executeNextTopOfStack3;

          rExecuteIoAddress0       <= executeIoAddress0;
          rExecuteIoReadWriteMode0 <= executeIoReadWriteMode0;
          rExecuteIoWriteValue0    <= executeIoWriteValue0;
          rExecuteIoReadRegister0  <= executeIoReadRegister0;

          fetchInstructionUseInternalProgramCounter <= executeProgramCounterIsIncremented;

          if (wUpdateCoreMessage)
            begin
              coreMessage                <= executeMessage;
              coreMessageChannel         <= executeMessageChannel;
              coreMessageMessage         <= executeMessageMessage;
              coreMessageNumWords        <= executeMessageNumWords;
              coreMessageJumpDestination <= executeMessageJumpDestination;
              if (executeMessage == `CORE_MESSAGE_ALT_START)
                coreHadMessageInAlt <= 0;
            end
        end
      else if (state == STATE_IO && ioFinished)
        begin
          fetchInstructionUseInternalProgramCounter <= 0;
          programCounter   <= ioNextProgramCounter;
          stackPointer     <= ioNextStackPointer;
          callStackPointer <= ioNextCallStackPointer;
          topOfStack1      <= ioNextTopOfStack1;
          topOfStack2      <= ioNextTopOfStack2;
          topOfStack3      <= ioNextTopOfStack3;
        end
      else if (state == STATE_PUSH_NEXT_LOWER)
        topOfStack1      <= { topOfStack1[15:8], fetchedInstruction };
      else if (state == STATE_PUSH_NEXT_UPPER)
        topOfStack1      <= { topOfStack1[15:12], fetchedInstruction, 4'b0000 };
      else if (state == STATE_AWAIT)
        begin
          if (wUpdatePCAndTopOfStack)
            begin
              programCounter <= wNewPC;
              stackPointer   <= stackPointer - 1;
              topOfStack1    <= wNewTopOfStack;
              topOfStack2    <= topOfStack1;
              topOfStack3    <= topOfStack2;
            end
            coreHadMessageInAlt <= wCoreHadMessageInAlt;
        end

      if (wDisableFetchInternalPC)
        fetchInstructionUseInternalProgramCounter <= 0;

      if (state == STATE_PUSH_NEXT_LOWER || state == STATE_PUSH_NEXT_UPPER)
        stackPushFinished <= 1;
      else
        stackPushFinished <= 0;

      if (wClearCoreMessage)
        coreMessage <= `CORE_MESSAGE_NONE;

      if (wUpdateNeedsSaveAwait)
        rNeedsSaveAwait <= wNextNeedsSaveAwait;

      rPCOnAltEnd            <= wPCOnAltEnd;
      rNewTopOfStackOnAltEnd <= wNewTopOfStackOnAltEnd;

      if (!reset)
        begin
          state            <= STATE_AWAIT;
          programCounter   <= 0;
          stackPointer     <= 0;
          callStackPointer <= 2; // See saveState.v
          rNeedsSaveAwait <= 0;
          coreHadMessageInAlt <= 0;
        end
      else
        state <= nextState;
    end

  assign readyToReceive = state == STATE_AWAIT;
  assign executing = state == STATE_FETCH_STACK || state == STATE_FETCH_INSTRUCTION || state == STATE_EXECUTE || state == STATE_IO || state == STATE_PUSH_NEXT_LOWER || state == STATE_PUSH_NEXT_UPPER || state == STATE_SAVE;

  // SECTION: state transitions

  // NOTE: Because you can only have always @(*) block per module, I had to combine some of the
  // memory controller logic. This is probably a good argument for moving the memory control logic
  // into a separate module.
  always @(*)
    begin
      wFetchStackEnabled = 0;
      wFetchInstructionEnabled = 0;
      wUpdateCoreMessage = 0;
      wClearCoreMessage = 0;
      wUpdateNeedsSaveAwait = 0;
      wNextNeedsSaveAwait = 0;
      wUpdatePCAndTopOfStack = 0;
      wNewPC = programCounter;
      wNewTopOfStack = {dataBits{1'bx}};
      wDisableFetchInternalPC = 0;
      wPCOnAltEnd = rPCOnAltEnd;
      wNewTopOfStackOnAltEnd = rNewTopOfStackOnAltEnd;
      wCoreHadMessageInAlt = coreHadMessageInAlt;
      case (state)
        STATE_FETCH_STACK:
          begin
            componentWithMemoryControl = ComponentIDFetch;
            wFetchStackEnabled = reset;
            nextState = fetchStackFinished ? STATE_FETCH_INSTRUCTION : STATE_FETCH_STACK;
          end
        STATE_FETCH_INSTRUCTION:
          begin
            componentWithMemoryControl = ComponentIDFetch; // Doesn't matter but this is safe
            wFetchInstructionEnabled = 1;
            nextState = fetchInstructionFinished ? STATE_EXECUTE : STATE_FETCH_INSTRUCTION;
          end
        STATE_EXECUTE:
          begin
            wFetchInstructionEnabled = 1;
            componentWithMemoryControl = ComponentIDExecute;
            wUpdateCoreMessage = executeFinished;
            if (executeMessage != `CORE_MESSAGE_NONE)
              begin
                wUpdateNeedsSaveAwait = 1;
                wNextNeedsSaveAwait   = 1;
              end
            if (executeFinished)
              if (executeStatus == `EXEC_STATUS_OK)
                if (executeIoEnabled0)
                  nextState = STATE_IO;
                else if (executeNeedsFullFetch)
                  nextState = STATE_FETCH_STACK;
                else if (executePushNextLower)
                  nextState = STATE_PUSH_NEXT_LOWER;
                else if (executePushNextUpper)
                  nextState = STATE_PUSH_NEXT_UPPER;
                else if (executeProgramCounterIsIncremented)
                  nextState = wNextNeedsSaveAwait ? STATE_SAVE_AWAIT : STATE_EXECUTE;
                else
                  nextState = wNextNeedsSaveAwait ? STATE_SAVE_AWAIT : STATE_FETCH_INSTRUCTION;
              else
                nextState = STATE_SAVE;
            else
              nextState = STATE_EXECUTE;
          end
        STATE_IO:
          begin
            componentWithMemoryControl = ComponentIDIO;
            if (ioFinished)
              if (rNeedsSaveAwait)
                nextState = STATE_SAVE_AWAIT;
              else
                nextState = STATE_FETCH_INSTRUCTION;
            else
              nextState = STATE_IO;
          end
        STATE_PUSH_NEXT_LOWER:
          begin
            wFetchInstructionEnabled = 1;
            nextState = stackPushFinished ? STATE_EXECUTE : STATE_PUSH_NEXT_LOWER;
            componentWithMemoryControl = ComponentIDNone;
          end
        STATE_PUSH_NEXT_UPPER:
          begin
            wFetchInstructionEnabled = 1;
            nextState = stackPushFinished ? STATE_EXECUTE : STATE_PUSH_NEXT_UPPER;
            componentWithMemoryControl = ComponentIDNone;
          end
        STATE_SAVE:
          begin
            componentWithMemoryControl = ComponentIDSave;
            nextState = saveStateFinished ? STATE_AWAIT : STATE_SAVE;
          end
        STATE_RESUME:
          begin
            componentWithMemoryControl = ComponentIDResume;
            nextState = resumeStateFinished ? STATE_FETCH_STACK : STATE_RESUME;
          end
        STATE_SAVE_AWAIT:
          begin
            componentWithMemoryControl = ComponentIDSave;
            nextState = saveStateFinished ? STATE_AWAIT : STATE_SAVE_AWAIT;
            wUpdateNeedsSaveAwait = 1;
            wNextNeedsSaveAwait = 0;
          end
        STATE_AWAIT:
          begin
            nextState = STATE_AWAIT;
            componentWithMemoryControl = ComponentIDNone;
            if (processorMessage != `PROCESSOR_MESSAGE_NONE)
              wClearCoreMessage = 1;
            case (processorMessage)
              `PROCESSOR_MESSAGE_RESUME:
                nextState = STATE_RESUME;
              `PROCESSOR_MESSAGE_RECEIVE:
                begin
                  wUpdatePCAndTopOfStack = 1;
                  wNewTopOfStack = processorMessagePushValue;
                  nextState = STATE_FETCH_INSTRUCTION;
                  wDisableFetchInternalPC = 1;
                  // New PC set above
                end
              `PROCESSOR_MESSAGE_RECEIVE_AND_JUMP:
                begin
                  wUpdatePCAndTopOfStack = 1;
                  wNewTopOfStack = processorMessagePushValue;
                  wNewPC = processorMessageJumpDestination;
                  nextState = STATE_FETCH_INSTRUCTION;
                  wDisableFetchInternalPC = 1;
                end
              // This only occurs in response to altdisable instructions
              `PROCESSOR_MESSAGE_RECEIVE_AND_JUMP_AND_WAIT:
                begin
                  wNewTopOfStackOnAltEnd = processorMessagePushValue;
                  wPCOnAltEnd = processorMessageJumpDestination;
                  nextState = STATE_FETCH_INSTRUCTION;
                  wDisableFetchInternalPC = 1;
                  wCoreHadMessageInAlt = 1;
                end
              `PROCESSOR_MESSAGE_RESUME_AND_WAIT:
                nextState = STATE_RESUME_WAIT;
              default:
                begin end
            endcase
          end
        STATE_RESUME_WAIT:
          begin
            componentWithMemoryControl = ComponentIDResume;
            nextState = resumeStateFinished ? STATE_AWAIT : STATE_RESUME_WAIT;
          end
        default:
          begin
            componentWithMemoryControl = ComponentIDNone;
            nextState = state == STATE_AWAIT ? state : state + 1;
          end
      endcase
    end

endmodule
