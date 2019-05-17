`include "defaults.vh"

// Should be reset after use. Based on the Rust code.
module Disable #(parameter addrBits  = `ADDRESS_BITS, parameter dataBits  = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    input  wire                enabled,
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
    input  wire [addrBits-1:0] rxPid,
    input  wire                rxHadMessageInAlt,
    // Section: feature outputs
    output reg                 shouldScheduleSender,
    output reg  [addrBits-1:0] scheduleTxPid,
    output reg                 hasDeliveredMessage,
    output reg  [dataBits-1:0] deliveredMessage,
    output reg                 rxHasMessageInAlt
  );

  // Memory signals
  wire [addrBits-1:0] messageAddress = channel + 1;

  // State
  localparam STATE_INIT            = 3'd0;
  localparam STATE_READ_TX_PROC    = 3'd1;
  localparam STATE_HANDLE_TX_PROC  = 3'd2;
  localparam STATE_WRITE_RX_PROC_0 = 3'd3;
  localparam STATE_READ_MESSAGE_0  = 3'd4;
  localparam STATE_READ_MESSAGE_1  = 3'd5;

  reg [2:0] rState;

  // Signals

  reg [2:0]          wNextState;
  reg                wHasMessage;
  reg [dataBits-1:0] wMessage;
  reg                wShouldScheduleSender;
  reg                wFinished;
  reg                wUpdateTx;
  reg                wUpdateMessage;
  reg                wRxHasMessageInAlt;

  // Signal processing
  always @(posedge clk)
  begin
    if (!reset)
      rxHasMessageInAlt <= 0;
    if (!enabled)
      begin
        rState               <= STATE_INIT;
        shouldScheduleSender <= 0;
        finished             <= 0;
        hasDeliveredMessage  <= 0;
      end
    else
      begin
        rState <= wNextState;
        finished <= wFinished;

        if (wUpdateTx)
          scheduleTxPid <= dataOut[7:0];

        if (wShouldScheduleSender)
          shouldScheduleSender <= 1;

        if (wUpdateMessage)
          deliveredMessage <= wMessage;

        if (wHasMessage)
          hasDeliveredMessage <= 1;

        rxHasMessageInAlt <= wRxHasMessageInAlt;
      end
  end

  // Combinatorial logic
  always @(*)
  begin
    address               = {addrBits{1'bx}};
    dataIn                = {dataBits{1'bx}};
    readWriteMode         = `RAM_READ;
    wFinished             = 0;
    wNextState            = rState + 1;
    wHasMessage           = 0;
    wMessage              = {dataBits{1'bx}};
    wShouldScheduleSender = 0;
    wFinished             = 0;
    wUpdateTx             = 0;
    wUpdateMessage        = 0;
    wRxHasMessageInAlt    = rxHadMessageInAlt;
    case (rState)
      STATE_INIT:
        begin
          address = channel;
          wRxHasMessageInAlt = rxHadMessageInAlt;
        end
      STATE_READ_TX_PROC:
        begin
          wUpdateTx = 1;
          address   = channel;
        end
      STATE_HANDLE_TX_PROC:
        begin
          if (scheduleTxPid == rxPid) // Then clear, because nothing was sent to this channel
            begin
              address       = channel;
              dataIn        = 0;
              readWriteMode = `RAM_WRITE;
            end
          else
            begin
              if (rxHadMessageInAlt) // Do nothing, as we've already decided on another channel
                wFinished = 1;
              else
                begin
                  // Has a message on this channel and none of the previous
                  // channels have been sent to.
                  wShouldScheduleSender = 1;
                  wHasMessage = 1;
                  // As above, clear the channel and progress
                  address       = channel;
                  dataIn        = 0;
                  readWriteMode = `RAM_WRITE;
                end
            end
        end
      STATE_WRITE_RX_PROC_0:
        begin
          address       = channel;
          dataIn        = 0;
          readWriteMode = `RAM_WRITE;
          // If we have to read a message then continue
          wFinished     = ~hasDeliveredMessage;
        end
      STATE_READ_MESSAGE_0:
        begin
          address = messageAddress; // Start reading on this cycle
        end
      STATE_READ_MESSAGE_1:
        begin
          wFinished      = 1;
          address        = messageAddress;
          wUpdateMessage = 1;
          wMessage       = dataOut;
          wRxHasMessageInAlt = 1;
        end
      default:
        begin
        end
    endcase
  end

endmodule
