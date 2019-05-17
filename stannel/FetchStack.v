`include "defaults.vh"

// The inputs and outputs of this stage are already registered.
module FetchStack #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    input  wire [dataBits-1:0] dataOut,
    output wire [addrBits-1:0] address,
    output wire                finished,
    input  wire [addrBits-1:0] stackPointer,
    output wire [dataBits-1:0] topOfStack1,
    output wire [dataBits-1:0] topOfStack2,
    output wire [dataBits-1:0] topOfStack3
  );

  // Section: Data path

  reg [dataBits-1:0] rTop1, rTop2, rTop3;

  assign topOfStack1 = rTop1;
  assign topOfStack2 = rTop2;
  assign topOfStack3 = rTop3;

  reg [addrBits-1:0] wOffset;
  assign address = stackPointer + wOffset;

  assign finished = rState == FETCH_DONE;

  // Section: Controller

  localparam FETCH_TOP1 = 2'd0;
  localparam FETCH_TOP2 = 2'd1;
  localparam FETCH_TOP3 = 2'd2;
  localparam FETCH_DONE = 2'd3;

  reg wUpdateTop1;
  reg wUpdateTop2;
  reg wUpdateTop3;

  reg [1:0] rState;
  reg       rMemoryCycle;

  always @(posedge clk)
    begin
      if (wUpdateTop1)
        rTop1 <= dataOut;
      if (wUpdateTop2)
        rTop2 <= dataOut;
      if (wUpdateTop3)
        rTop3 <= dataOut;

      if (!reset)
        rMemoryCycle <= 0;
      else
        rMemoryCycle <= rMemoryCycle + 1;

      if (!reset)
        rState <= 0;
      else if (rMemoryCycle)
        rState <= rState + 1;
    end

  always @(*)
    begin
      wUpdateTop1 = 0;
      wUpdateTop2 = 0;
      wUpdateTop3 = 0;
      wOffset     = 0;
      case (rState)
        FETCH_TOP1:
        begin
          wOffset     = 0;
          wUpdateTop1 = rMemoryCycle;
        end
        FETCH_TOP2:
        begin
          wOffset     = 1;
          wUpdateTop2 = rMemoryCycle;
        end
        FETCH_TOP3:
        begin
          wOffset     = 2;
          wUpdateTop3 = rMemoryCycle;
        end
        default:
        begin
          wOffset = 0;
        end
      endcase
    end

endmodule
