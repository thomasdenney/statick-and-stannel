`include "defaults.vh"
`include "opcodes.vh"
`include "status.vh"
`include "messages.vh"

module MessageDelivery #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    output reg                 finished,
    // Section: memory I/Os
    output reg                 memoryCellReadWriteMode,
    output reg  [addrBits-1:0] memoryCellAddress,
    output reg  [dataBits-1:0] memoryCellDataIn,
    input  wire [dataBits-1:0] memoryCellDataOut,
    // Section: processor state
    input  wire [addrBits-1:0] core0Process,
    input  wire [addrBits-1:0] core1Process,
    // Section: features
    input  wire [addrBits-1:0] targetProcess,
    input  wire [dataBits-1:0] message,
    input  wire                needsJump,
    input  wire [8:0]          jumpDestination,
    output reg                 deliverMessageToCore0,
    output reg                 deliverMessageToCore1
  );

  localparam STATE_INIT_READ_STACK_POINTER      = 3'd0;
  localparam STATE_MEMORY_WRITE_STACK_POINTER   = 3'd1;
  localparam STATE_MEMORY_WRITE_TOP_OF_STACK    = 3'd2;
  localparam STATE_MEMORY_READ_PROGRAM_COUNTER  = 3'd3;
  localparam STATE_MEMORY_WRITE_PROGRAM_COUNTER = 3'd4;

  // State
  reg                rIoTicker;
  reg [2:0]          rState;
  reg [dataBits-1:0] rOldData;

  // Signals
  reg [2:0] wNextState;
  reg       wFinished;
  reg       wSaveOutput;

  reg wDeliverMessageToCore0;
  reg wDeliverMessageToCore1;

  wire [addrBits-1:0] oldStackPointer = rOldData[15:8];
  wire [addrBits-1:0] oldCallStackPointer = rOldData[7:0];
  wire [addrBits-1:0] newStackPointer = oldStackPointer - 1;
  wire [dataBits-1:0] newStackPointers = { newStackPointer, oldCallStackPointer };

  wire [dataBits-1:0] newAluFlagsAndPC = { rOldData[15:9], jumpDestination };

  always @(posedge clk)
    begin
      if (!reset)
        begin
          rState    <= STATE_INIT_READ_STACK_POINTER;
          rIoTicker <= 0;
          finished  <= 0;
          deliverMessageToCore0 <= 0;
          deliverMessageToCore1 <= 0;
        end
      else
        begin
          // Allow updates to |finished| in the init state in the case we can
          // terminate immediately with message delivery directly to a core.
          if (rIoTicker || rState == STATE_INIT_READ_STACK_POINTER)
            finished <= wFinished;

          if (rIoTicker)
            rState <= wNextState;

          rIoTicker <= rIoTicker + 1;

          if (wSaveOutput)
            rOldData <= memoryCellDataOut;

          if (wFinished)
            begin
              deliverMessageToCore0 <= wDeliverMessageToCore0;
              deliverMessageToCore1 <= wDeliverMessageToCore1;
            end
        end
    end


  always @(*)
    begin
      memoryCellReadWriteMode = `RAM_READ;
      memoryCellAddress       = {addrBits{1'bx}};
      memoryCellDataIn        = {dataBits{1'bx}};
      wNextState              = rState;
      wFinished               = 0;
      wSaveOutput             = 0;
      wDeliverMessageToCore0  = 0;
      wDeliverMessageToCore1  = 0;

      case (rState)
        STATE_INIT_READ_STACK_POINTER:
          begin
            memoryCellAddress = 0;
            wSaveOutput       = 1;
            if (core0Process == targetProcess)
              begin
                wDeliverMessageToCore0 = 1;
                wFinished              = 1;
              end
            else if (core1Process == targetProcess)
              begin
                wDeliverMessageToCore1 = 1;
                wFinished              = 1;
              end
            // The super-module will set |reset| to 0 if |finished| is true on
            // the next cycle, so this will actually be reset to the initial
            // state within a cycle.
            wNextState = STATE_MEMORY_WRITE_STACK_POINTER;
          end
        STATE_MEMORY_WRITE_STACK_POINTER:
          begin
            memoryCellAddress       = 0;
            memoryCellReadWriteMode = `RAM_WRITE;
            memoryCellDataIn        = newStackPointers;
            wNextState              = STATE_MEMORY_WRITE_TOP_OF_STACK;
            end
        STATE_MEMORY_WRITE_TOP_OF_STACK:
          begin
            memoryCellAddress       = newStackPointer;
            memoryCellReadWriteMode = `RAM_WRITE;
            memoryCellDataIn        = message;
            wFinished               = !needsJump;
            if (needsJump)
              wNextState            = STATE_MEMORY_READ_PROGRAM_COUNTER;
            end
        STATE_MEMORY_READ_PROGRAM_COUNTER:
          begin
            memoryCellAddress = 1;
            wSaveOutput       = 1;
            wNextState        = STATE_MEMORY_WRITE_PROGRAM_COUNTER;
          end
        STATE_MEMORY_WRITE_PROGRAM_COUNTER:
          begin
            memoryCellAddress       = 1;
            memoryCellReadWriteMode = `RAM_WRITE;
            memoryCellDataIn        = newAluFlagsAndPC;
            wFinished               = 1;
          end
        default:
          begin
          end
      endcase
    end

endmodule
