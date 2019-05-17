`include "defaults.vh"

// Should be reset after use
module Send #(parameter addrBits  = `ADDRESS_BITS, parameter dataBits  = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    output reg                 finished,
    // Section: memory I/Os
    output reg  [addrBits-1:0] address,
    output reg                 readWriteMode,
    // verilator lint_off UNUSED
    input  wire [dataBits-1:0] dataOut,
    // verilator lint_on UNUSED
    output reg  [dataBits-1:0] dataIn,
    // Section: feature inputs
    input  wire [addrBits-1:0] channel,
    input  wire [dataBits-1:0] message,
    input  wire [addrBits-1:0] txPid,
    input  wire [`CELL_COUNT:0] alternationSet,
    input  wire [`CELL_COUNT:0] alternationReadySet,
    // Section: feature outputs
    output reg                 shouldScheduleReceiver,
    output reg                 shouldDescheduleSender,
    output reg  [addrBits-1:0] scheduleRxPid,
    output reg                 addToAlternationReadySet,
    // The super-module should handle the pushing of the message to the correct
    // memory cell *or* core. This output is the same as the input message.
    output reg  [dataBits-1:0] deliveredMessage
  );

  // Memory
  wire [addrBits-1:0] messageAddress = channel + 1;

  // Alternation set
  wire [`CELL_COUNT:0] alternationFlag = `CELL_COUNT_CONST_1 << scheduleRxPid;
  wire inAlternationSet = (alternationSet & alternationFlag) != 0;
  wire inAlternationReadySet = (alternationReadySet & alternationFlag) != 0;

  // State

  localparam STATE_INIT            = 3'd0;
  localparam STATE_READ_RX_PROC    = 3'd1;
  localparam STATE_HANDLE_RX_PROC  = 3'd2;
  localparam STATE_NULL_RX_PROC    = 3'd3;
  localparam STATE_ALT_RX_PROC     = 3'd4;
  localparam STATE_NORMAL_RX_PROC  = 3'd5;
  localparam STATE_WRITE_TX_PROC_0 = 3'd6;
  localparam STATE_WRITE_TX_PROC_1 = 3'd7;

  reg [2:0] rState;
  reg [dataBits-1:0] rPidToWrite;

  // Signals

  reg        wSaveMessage;
  reg        wFinished;
  reg [2:0]  wNextState;
  reg        wUpdateRxPid;
  reg        wShouldScheduleReceiver;
  reg        wShouldDescheduleSender;
  reg        wAddToAlternationReadySet;

  reg                wUpdatePidToWrite;
  reg [dataBits-1:0] wPidToWrite;

  // Signal processing
  always @(posedge clk)
  begin
    if (!reset)
      begin
        rState                   <= STATE_INIT;
        rPidToWrite              <= 0;
        shouldScheduleReceiver   <= 0;
        shouldDescheduleSender   <= 0;
        finished                 <= 0;
        addToAlternationReadySet <= 0;
      end
    else
      begin
        rState <= wNextState;
        finished <= wFinished;

        if (wUpdateRxPid)
          scheduleRxPid <= dataOut[7:0];

        if (wShouldScheduleReceiver)
          shouldScheduleReceiver <= 1;

        if (wShouldDescheduleSender)
          shouldDescheduleSender <= 1;

        if (wUpdatePidToWrite)
          rPidToWrite <= wPidToWrite;

        if (wSaveMessage)
          deliveredMessage <= message;
        addToAlternationReadySet <= wAddToAlternationReadySet;
      end
  end

  // Combinatorial logic
  always @(*)
  begin
    address                   = {addrBits{1'bx}};
    dataIn                    = {dataBits{1'bx}};
    readWriteMode             = `RAM_READ;
    wFinished                 = 0;
    wUpdateRxPid              = 0;
    wSaveMessage              = 0;
    wShouldScheduleReceiver   = 0;
    wShouldDescheduleSender   = 0;
    wUpdatePidToWrite         = 0;
    wPidToWrite               = {dataBits{1'bx}};
    wNextState                = rState;
    wAddToAlternationReadySet = addToAlternationReadySet;
    case (rState)
      STATE_INIT:
        begin
          address = channel;
          wNextState = STATE_READ_RX_PROC;
          wSaveMessage = 1;
        end
      STATE_READ_RX_PROC:
        begin
          address = channel;
          wUpdateRxPid = 1;
          wNextState = STATE_HANDLE_RX_PROC;
        end
      STATE_HANDLE_RX_PROC:
        begin
          address           = messageAddress;
          dataIn            = message;
          readWriteMode     = `RAM_WRITE;
          wUpdatePidToWrite = 1;
          wPidToWrite = {8'b0, txPid};
          if (scheduleRxPid == 0)
            begin
              wNextState = STATE_NULL_RX_PROC;
              wShouldDescheduleSender = 1;
            end
          else if (inAlternationSet && ~inAlternationReadySet)
            begin
              wAddToAlternationReadySet = 1;
              wNextState = STATE_ALT_RX_PROC;
              wShouldScheduleReceiver = ~inAlternationReadySet;
              // See the logic in the Rust implementation. This is handled in
              // the sender's disable channel.
              wShouldDescheduleSender = 1;
            end
          else
            begin
              wNextState = STATE_NORMAL_RX_PROC;
              // We should not schedule the receiver if it is an alternation and
              // already received a message on another arm's channel.
              wShouldScheduleReceiver = ~inAlternationReadySet;
              // Similarly, we should deschedule the sender if it is an
              // alternation and already received a message on another arm's
              // channel
              wShouldDescheduleSender = inAlternationReadySet;
              wPidToWrite = 0;
            end
        end
      STATE_NULL_RX_PROC:
        begin
          address       = messageAddress;
          dataIn        = message;
          readWriteMode = `RAM_WRITE;
          wNextState    = STATE_WRITE_TX_PROC_0;
        end
      STATE_ALT_RX_PROC:
        begin
          address       = messageAddress;
          dataIn        = message;
          readWriteMode = `RAM_WRITE;
          wNextState    = STATE_WRITE_TX_PROC_0;
        end
      STATE_NORMAL_RX_PROC:
        begin
          address       = messageAddress;
          dataIn        = message;
          readWriteMode = `RAM_WRITE;
          wNextState    = STATE_WRITE_TX_PROC_1;
        end
      STATE_WRITE_TX_PROC_0:
        begin
          address       = channel;
          dataIn        = rPidToWrite;
          readWriteMode = `RAM_WRITE;
          wNextState    = STATE_WRITE_TX_PROC_1;
        end
      STATE_WRITE_TX_PROC_1:
        begin
          address       = channel;
          dataIn        = rPidToWrite;
          readWriteMode = `RAM_WRITE;
          wNextState    = STATE_INIT;
          wFinished     = 1;
        end
      default:
        begin
        end
    endcase
  end

endmodule
