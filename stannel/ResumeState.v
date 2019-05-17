`include "defaults.vh"

// The inputs and outputs of this stage are already registered.
module ResumeState #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    input  wire [dataBits-1:0] dataOut,
    output wire [addrBits-1:0] address,
    output wire                rwMode,
    output wire                finished,
    // Section: feature outputs (all registered)
    output wire [addrBits-1:0] stackPointer,
    output wire [addrBits-1:0] callStackPointer,
    output wire [8:0]          programCounter,
    output wire [3:0]          aluFlags
  );

  // Section: Data path

  reg [addrBits-1:0] rStackPointer, rCallStackPointer;
  reg [8:0] rProgramCounter;
  reg [3:0] rAluFlags;

  assign stackPointer     = rStackPointer;
  assign callStackPointer = rCallStackPointer;
  assign programCounter   = rProgramCounter;
  assign aluFlags         = rAluFlags;

  reg [addrBits-1:0] wAddress;
  assign address = wAddress;
  assign rwMode = `RAM_READ;

  assign rwMode = `RAM_READ;

  reg rRamCycle;
  reg [1:0] rState;

  localparam LOAD_STACK_POINTERS            = 2'd0;
  localparam LOAD_PROGRAM_COUNTER_AND_FLAGS = 2'd1;
  localparam LOAD_DONE                      = 2'd2;

  assign finished = rState == LOAD_DONE;

  reg wUpdateStackPointers;
  reg wUpdateProgramCounterAndAlu;

  // Section: Controller

  always @(posedge clk)
  begin
    if (!reset)
      rRamCycle <= 0;
    else
      rRamCycle <= rRamCycle + 1;

    if (wUpdateStackPointers)
    begin
      rStackPointer     <= dataOut[15:8];
      rCallStackPointer <= dataOut[7:0] + 8'd2;
    end

    if (wUpdateProgramCounterAndAlu)
    begin
      rProgramCounter   <= dataOut[8:0];
      rAluFlags         <= dataOut[15:12];
    end

    if (!reset)
      rState <= 0;
    else if (rRamCycle)
      rState <= rState + 1;
  end

  always @(*)
  begin
    wUpdateStackPointers = 0;
    wUpdateProgramCounterAndAlu = 0;
    wAddress = {addrBits{1'bx}};
    case (rState)
      LOAD_STACK_POINTERS:
      begin
        wAddress = 0;
        wUpdateStackPointers = rRamCycle;
      end
      LOAD_PROGRAM_COUNTER_AND_FLAGS:
      begin
        wAddress = 1;
        wUpdateProgramCounterAndAlu = rRamCycle;
      end
      default:
      begin
      end
    endcase
  end
endmodule
