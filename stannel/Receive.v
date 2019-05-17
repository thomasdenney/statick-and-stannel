`include "defaults.vh"

// Should be reset after use. A simpler version of the send module, again based
// on the Rust code.
module Receive #(parameter addrBits  = `ADDRESS_BITS, parameter dataBits  = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    output reg                 finished,
    // Section: memory I/Os
    output reg  [addrBits-1:0] address,
    output reg                 readWriteMode,
    input  wire [dataBits-1:0] dataOut,
    output reg  [dataBits-1:0] dataIn,
    // Section: feature inputs
    input  wire [addrBits-1:0] channel,
    input  wire [addrBits-1:0] rxPid,
    // Section: feature outputs
    output reg                 shouldScheduleSender,
    output reg                 shouldDescheduleReceiver,
    output reg  [addrBits-1:0] scheduleTxPid,
    output reg                 hasDeliveredMessage,
    output reg  [dataBits-1:0] deliveredMessage
  );

  // Memory signals
  wire [addrBits-1:0] messageAddress = channel + 1;

  // State

  localparam STATE_INIT            = 3'd0;
  localparam STATE_READ_TX_PROC    = 3'd1;
  localparam STATE_HANDLE_TX_PROC  = 3'd2;
  localparam STATE_WRITE_RX_PROC_0 = 3'd3;
  localparam STATE_WRITE_RX_PROC_1 = 3'd4;
  localparam STATE_READ_MESSAGE    = 3'd5;
  localparam STATE_WRITE_0         = 3'd6;
  localparam STATE_WRITE_1         = 3'd7;

  reg [2:0]          rState;

  // Signals

  reg [2:0]          wNextState;
  reg                wHasMessage;
  reg [dataBits-1:0] wMessage;
  reg                wShouldScheduleSender;
  reg                wShouldDescheduleReceiver;
  reg                wFinished;
  reg                wUpdateTx;
  reg                wUpdateMessage;
  reg                wUpdateScheduling;

  // Signal processing
  always @(posedge clk)
  begin
    if (!reset)
      begin
        rState                    <= STATE_INIT;
        shouldScheduleSender     <= 0;
        shouldDescheduleReceiver <= 0;
        finished                 <= 0;
        hasDeliveredMessage      <= 0;
      end
    else
      begin
        rState <= wNextState;
        finished <= wFinished;

        if (wUpdateTx)
          scheduleTxPid <= dataOut[7:0];

        if (wUpdateScheduling)
          begin
            shouldScheduleSender     <= wShouldScheduleSender;
            shouldDescheduleReceiver <= wShouldDescheduleReceiver;
            hasDeliveredMessage      <= wHasMessage;
          end

        if (wUpdateMessage)
          deliveredMessage <= wMessage;
      end
  end

  // Combinatorial logic
  always @(*)
  begin
    address                   = {addrBits{1'bx}};
    dataIn                    = {dataBits{1'bx}};
    readWriteMode             = `RAM_READ;
    wFinished                 = 0;
    wNextState                = rState;
    wHasMessage               = 0;
    wMessage                  = {dataBits{1'bx}};
    wShouldScheduleSender     = 0;
    wShouldDescheduleReceiver = 0;
    wFinished                 = 0;
    wUpdateTx                 = 0;
    wUpdateMessage            = 0;
    wUpdateScheduling         = 0;
    case (rState)
      STATE_INIT:
        begin
          address    = channel;
          wNextState = STATE_READ_TX_PROC;
        end
      STATE_READ_TX_PROC:
        begin
          wUpdateTx  = 1;
          address    = channel;
          wNextState = STATE_HANDLE_TX_PROC;
        end
      STATE_HANDLE_TX_PROC:
        begin
          wUpdateScheduling         = 1;
          wShouldDescheduleReceiver = scheduleTxPid == 0;
          wShouldScheduleSender     = scheduleTxPid != 0;
          wHasMessage               = scheduleTxPid != 0;
          wNextState                = scheduleTxPid == 0 ? STATE_WRITE_RX_PROC_0 : STATE_READ_MESSAGE;
          address                   = messageAddress; // Start the read of the message on this cycle.
        end
      STATE_WRITE_RX_PROC_0:
        begin
          address       = channel;
          dataIn        = {8'b0, rxPid};
          readWriteMode = `RAM_WRITE;
          wNextState    = STATE_WRITE_RX_PROC_1;
        end
      STATE_WRITE_RX_PROC_1:
        begin
          address       = channel;
          dataIn        = {8'b0,rxPid};
          readWriteMode = `RAM_WRITE;
          wNextState    = STATE_INIT;
          wFinished     = 1;
        end
      STATE_READ_MESSAGE:
        begin
          address        = messageAddress; // Finish reading message on this cycle
          wUpdateMessage = 1;
          wMessage       = dataOut;
          wNextState     = STATE_WRITE_0;
        end
      STATE_WRITE_0:
        begin
          address       = channel;
          dataIn        = 0;
          readWriteMode = `RAM_WRITE;
          wNextState    = STATE_WRITE_1;
        end
      STATE_WRITE_1:
        begin
          address       = channel;
          dataIn        = 0;
          readWriteMode = `RAM_WRITE;
          wNextState    = STATE_INIT;
          wFinished     = 1;
        end
    endcase
  end

endmodule
