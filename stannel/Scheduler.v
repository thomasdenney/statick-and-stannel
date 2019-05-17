`include "defaults.vh"
`include "opcodes.vh"
`include "status.vh"
`include "messages.vh"

module Scheduler #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    input  wire                enabled,
    output reg                 finished,
    // Section: processor state
    input  wire                core0ReadyForDeschedule,
    input  wire                core1ReadyForDeschedule,
    // Section: features
    input  wire                hasDeschedule,
    input  wire [addrBits-1:0] deschedulePid,
    input  wire                hasSchedule,
    input  wire [addrBits-1:0] schedulePid,
    // Section: Output (clocked registers)
    // NOTE: These registers are read from internally too.
    output reg                 core0Active,
    output reg  [addrBits-1:0] core0Pid,
    output reg                 core1Active,
    output reg  [addrBits-1:0] core1Pid,
    output reg                 core0NeedsResumeAwake,
    output reg                 core1NeedsResumeAwake,
    // Section: Output (non-clocked registers)
    // NOTE: Currently none, but I might add some later...
    output wire                canHalt
  );

  // Memory

  reg  [addrBits-1:0] wAddress;
  reg  [dataBits-1:0] wDataIn;
  // verilator lint_off UNUSED
  wire [dataBits-1:0] dataOut;
  // verilator lint_on UNUSED
  reg                 wReadWriteMode;

  // This is a really inefficient use of a memory module; only 20 bytes of
  // memory are actually required. Can they be spared somewhere else?
  IceRam #(.addrBits(addrBits), .dataBits(dataBits)) schedulerListMemory(
    .clk           (clk),
    .address       (wAddress),
    .dataIn        (wDataIn),
    .dataOut       (dataOut),
    .readWriteMode (wReadWriteMode)
  );

  // State

  reg [`CELL_COUNT:0] rScheduleState;

  // It is never possible for the schedule list to contain every possible
  // process because there is always at least one valid process ID pinned to one
  // of the cores, so wrapping arithmetic isn't an issue here. C++ naming
  // convention is used here; Front refers to the first element, End refers to
  // the index after the last entry of the list.
  reg [addrBits-1:0] rFrontOfIndexList;
  reg [addrBits-1:0] rEndOfIndexList;

  reg [3:0] rState;

  localparam STATE_INIT                            = 4'd0;
  localparam STATE_DESCHEDULE_START                = 4'd1;
  localparam STATE_DESCHEDULE_WAIT                 = 4'd2;
  localparam STATE_SCHEDULE_ADD_TO_SCHEDULE_LIST_0 = 4'd3;
  localparam STATE_SCHEDULE_ADD_TO_SCHEDULE_LIST_1 = 4'd4;
  localparam STATE_SCHEDULE_INIT                   = 4'd5;
  localparam STATE_SCHEDULE_READ_NEXT              = 4'd6;


  // Signals

  assign canHalt = rScheduleState == 0;

  reg [`CELL_COUNT:0] wNextScheduleState;

  reg [3:0]          wNextState;
  reg                wFinished;
  reg                wDeactivateCore0;
  reg                wDeactivateCore1;
  reg                wIncrementListFront;
  reg                wIncrementListEnd;
  reg                wActivateCore0;
  reg [addrBits-1:0] wCore0NewPid;
  reg                wActivateCore1;
  reg [addrBits-1:0] wCore1NewPid;

  always @(posedge clk)
    begin
      if (!reset)
        begin
          rState            <= STATE_INIT;
          rScheduleState    <= 0;
          finished          <= 0;
          rFrontOfIndexList <= 0;
          rEndOfIndexList   <= 0;
          core0Active       <= 0;
          core0Pid          <= 0;
          core1Active       <= 0;
          core1Pid          <= 0;
        end
      else if (!enabled)
        begin
          rState                <= STATE_INIT;
          finished              <= 0;
          core0NeedsResumeAwake <= 0;
          core1NeedsResumeAwake <= 0;
        end
      else
        begin
          rState   <= wNextState;
          finished <= wFinished;
          rScheduleState <= wNextScheduleState;

          if (wDeactivateCore0)
            core0Active <= 0;
          else if (wActivateCore0)
            begin
              core0Active           <= 1;
              core0NeedsResumeAwake <= 1;
              core0Pid              <= wCore0NewPid;
            end

          if (wDeactivateCore1)
            core1Active <= 0;
          else if (wActivateCore1)
            begin
              core1Active           <= 1;
              core1NeedsResumeAwake <= 1;
              core1Pid              <= wCore1NewPid;
            end

          if (wIncrementListFront)
            rFrontOfIndexList <= rFrontOfIndexList + 1;
          if (wIncrementListEnd)
            rEndOfIndexList <= rEndOfIndexList + 1;
        end
    end


  always @(*)
    begin
      wReadWriteMode      = `RAM_READ;
      wAddress            = {addrBits{1'bx}};
      wDataIn             = {dataBits{1'bx}};
      wNextState          = rState;
      wFinished           = 0;
      wDeactivateCore0    = 0;
      wDeactivateCore1    = 0;
      wIncrementListFront = 0;
      wIncrementListEnd   = 0;
      wNextScheduleState  = rScheduleState;
      wActivateCore0      = 0;
      wActivateCore1      = 0;
      wCore0NewPid        = 0;
      wCore1NewPid        = 0;

      case (rState)
        STATE_INIT:
          begin
            if (hasDeschedule)
              wNextState = STATE_DESCHEDULE_START;
            else if (hasSchedule)
              wNextState = STATE_SCHEDULE_ADD_TO_SCHEDULE_LIST_0;
            else
              wNextState = STATE_SCHEDULE_INIT;
          end
        STATE_DESCHEDULE_START:
          begin
            if (core0Pid == deschedulePid)
              wDeactivateCore0 = 1;
            if (core1Pid == deschedulePid)
              wDeactivateCore1 = 1;
            wNextState = STATE_DESCHEDULE_WAIT;
            wNextScheduleState = rScheduleState & ({{`CELL_COUNT{1'b1}}, 1'b1} ^ (`CELL_COUNT_CONST_1 << deschedulePid[4:0]));
          end
        STATE_DESCHEDULE_WAIT:
          begin
            if (core0Pid == deschedulePid && !core0ReadyForDeschedule)
              wNextState = STATE_DESCHEDULE_WAIT;
            else if (core1Pid == deschedulePid && !core1ReadyForDeschedule)
              wNextState = STATE_DESCHEDULE_WAIT;
            else if (hasSchedule)
              wNextState = STATE_SCHEDULE_ADD_TO_SCHEDULE_LIST_0;
            else
              wNextState = STATE_SCHEDULE_INIT;
          end
        STATE_SCHEDULE_ADD_TO_SCHEDULE_LIST_0:
          begin
            wAddress       = rEndOfIndexList;
            wDataIn        = {8'b0, schedulePid};
            wReadWriteMode = `RAM_WRITE;
            wNextState     = STATE_SCHEDULE_ADD_TO_SCHEDULE_LIST_1;
          end
        STATE_SCHEDULE_ADD_TO_SCHEDULE_LIST_1:
          begin
            wIncrementListEnd = 1;
            wAddress          = rEndOfIndexList;
            wDataIn           = {8'b0, schedulePid};
            wReadWriteMode    = `RAM_WRITE;
            wNextState        = STATE_SCHEDULE_INIT;
          end
        STATE_SCHEDULE_INIT:
          begin
            wAddress = rFrontOfIndexList;
            if (rFrontOfIndexList == rEndOfIndexList)
              wFinished = 1;
            else if (!core0Active && !core0ReadyForDeschedule)
              wNextState = STATE_SCHEDULE_INIT;
            else if (!core1Active && !core1ReadyForDeschedule)
              wNextState = STATE_SCHEDULE_INIT;
            else if (!core0Active)
              wNextState = STATE_SCHEDULE_READ_NEXT;
            else if (!core1Active)
              wNextState = STATE_SCHEDULE_READ_NEXT;
            else
              wFinished = 1;
          end
        STATE_SCHEDULE_READ_NEXT:
          begin
            wAddress            = rFrontOfIndexList;
            wIncrementListFront = 1;
            wNextState          = STATE_SCHEDULE_INIT;
            wNextScheduleState  = rScheduleState | (`CELL_COUNT_CONST_1 << dataOut[4:0]);
            if (!core0Active)
              begin
                wActivateCore0 = 1;
                wCore0NewPid   = dataOut[7:0];
                wFinished      = core1Active;
              end
            else
              begin
                wActivateCore1 = 1;
                wCore1NewPid   = dataOut[7:0];
                wFinished      = 1;
              end
          end
        default:
          begin
          end
      endcase
    end

endmodule
