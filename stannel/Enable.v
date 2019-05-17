`include "defaults.vh"

// Should be reset after use. Based on the Rust implementation.
module Enable #(parameter addrBits  = `ADDRESS_BITS, parameter dataBits  = `DATA_BITS) (
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
    input  wire [addrBits-1:0] rxPid,
    // Section: feature outputs
    output reg                 rxCanReceive
  );

  // State
  localparam STATE_INIT            = 3'd0;
  localparam STATE_READ_TX_PROC    = 3'd1;
  localparam STATE_HANDLE_TX_PROC  = 3'd2;
  localparam STATE_WRITE_RX_PROC_0 = 3'd3;
  localparam STATE_WRITE_RX_PROC_1 = 3'd4;

  reg [2:0]          rState;
  reg [addrBits-1:0] rTx;

  // Signals

  reg [2:0]          wNextState;
  reg                wFinished;
  reg [addrBits-1:0] wTx;
  reg                wUpdateTx;
  reg                wRxCanReceive;

  // Signal processing
  always @(posedge clk)
  begin
    if (!reset)
      begin
        rState            <= STATE_INIT;
        finished          <= 0;
        rxCanReceive <= 0;
        // newAlternationSet <= 0;
      end
    else
      begin
        rState            <= wNextState;
        finished          <= wFinished;
        rxCanReceive <= wRxCanReceive;

        if (wUpdateTx)
            rTx <= wTx;
      end
  end

  // Combinatorial logic
  always @(*)
  begin
    address       = {addrBits{1'bx}};
    dataIn        = {dataBits{1'bx}};
    readWriteMode = `RAM_READ;
    wNextState    = rState;
    wFinished     = 0;
    wUpdateTx     = 0;
    wTx           = {addrBits{1'bx}};
    wRxCanReceive = rxCanReceive;
    case (rState)
      STATE_INIT:
        begin
          address   = channel;
          wNextState = STATE_READ_TX_PROC;
        end
      STATE_READ_TX_PROC:
        begin
          wUpdateTx  = 1;
          wTx        = dataOut[7:0];
          address   = channel;
          wNextState = STATE_HANDLE_TX_PROC;
        end
      STATE_HANDLE_TX_PROC:
        begin
          if (rTx == 0)
            wNextState = STATE_WRITE_RX_PROC_0;
          else
            begin
              wFinished     = 1;
              wNextState    = STATE_INIT;
              wRxCanReceive = 1;
            end
        end
      STATE_WRITE_RX_PROC_0:
        begin
          address       = channel;
          dataIn        = {8'b0, rxPid};
          readWriteMode = `RAM_WRITE;
          wNextState     = STATE_WRITE_RX_PROC_1;
        end
      STATE_WRITE_RX_PROC_1:
        begin
          address       = channel;
          dataIn        = {8'b0,rxPid};
          readWriteMode = `RAM_WRITE;
          wNextState     = STATE_INIT;
          wFinished      = 1;
        end
      default:
        begin
        end
    endcase
  end

endmodule
