`include "defaults.vh"

// Do not reset after use. Instead, set |alloc| and |free| to 0.
module Heap #(
  parameter addrBits  = `ADDRESS_BITS, // Address bits must be less than or equal to data bits
  parameter dataBits  = `DATA_BITS,
  // Addresses are allocated as [heapBase..heapMax]
  parameter heapBase  = 0,
  parameter heapMax   = 8'hFF,
  parameter allocSize = 1) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    output reg                 finished,
    // Section: memory I/Os
    output reg  [addrBits-1:0] address,
    output reg                 readWriteMode,
    // verilator lint_off UNUSED
    input  wire [dataBits-1:0] dataOut,
    // verilator lint_off UNUSED
    output reg  [dataBits-1:0] dataIn,
    // Section: feature I/Os
    input  wire                alloc,
    output reg  [addrBits-1:0] allocAddress,
    input  wire                free,
    input  wire [addrBits-1:0] freeAddress
  );

  // State
  reg [addrBits-1:0] heapFree;
  reg [addrBits-1:0] heapEnd;

  localparam STATE_INIT             = 2'd0;
  localparam STATE_UPDATE_HEAP_FREE = 2'd1;
  localparam STATE_WRITE_FREE       = 2'd2;

  reg [1:0] rState;

  // Signals
  reg wIncrementHeapEnd;
  reg wUpdateHeapFreeFromMemory;
  reg wUpdateHeapFreeFromFreedAddress;
  reg wAllocFromHeapEnd;
  reg wFinished;

  reg [1:0] wNextState;

  // Signal processing
  always @(posedge clk)
  begin
    if (!reset)
      begin
        rState   <= STATE_INIT;
        heapFree <= 0;
        heapEnd  <= heapBase;
        finished <= 0;
      end
    else
      begin
        rState <= wNextState;
        finished <= wFinished;

        if (wIncrementHeapEnd)
          heapEnd <= heapEnd + allocSize;

        if (wAllocFromHeapEnd)
          allocAddress <= heapEnd;
        else if (wUpdateHeapFreeFromMemory)
          allocAddress <= heapFree;

        if (wUpdateHeapFreeFromMemory)
          heapFree <= dataOut[7:0];
        else if (wUpdateHeapFreeFromFreedAddress)
          heapFree <= freeAddress;
      end
  end

  // Combinatorial logic
  always @(*)
  begin
    address                         = {addrBits{1'bx}};
    dataIn                          = {dataBits{1'bx}};
    readWriteMode                   = `RAM_READ;
    wFinished                       = 0;
    wIncrementHeapEnd               = 0;
    wUpdateHeapFreeFromMemory       = 0;
    wUpdateHeapFreeFromFreedAddress = 0;
    wAllocFromHeapEnd               = 0;
    wNextState                      = rState;
    case (rState)
      STATE_INIT:
        begin
          if (alloc)
            begin
              if (heapEnd != heapMax)
                begin
                  wIncrementHeapEnd = 1;
                  wAllocFromHeapEnd = 1;
                  wFinished         = 1;
                  wNextState        = STATE_INIT;
                end
              else
                begin
                  address   = heapFree;
                  wNextState = STATE_UPDATE_HEAP_FREE;
                end
            end
          else if (free)
            begin
              address       = freeAddress;
              readWriteMode = `RAM_WRITE;
              dataIn        = { 8'b0, heapFree };
              wNextState    = STATE_WRITE_FREE;
            end
          else
            wNextState       = STATE_INIT;
        end
      STATE_UPDATE_HEAP_FREE:
        begin
          address                   = heapFree;
          wUpdateHeapFreeFromMemory = 1;
          wFinished                 = 1;
          wNextState                = STATE_INIT;
        end
      STATE_WRITE_FREE:
        begin
          // Continue the earlier write
          address       = freeAddress;
          readWriteMode = `RAM_WRITE;
          dataIn        = { 8'b0, heapFree };

          wNextState                      = STATE_INIT;
          wUpdateHeapFreeFromFreedAddress = 1;
          wFinished                       = 1;
        end
      default: begin end
    endcase
  end

endmodule
