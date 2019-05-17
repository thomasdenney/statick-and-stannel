`include "defaults.vh"

module FetchInstruction #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    input  wire                useInternalProgramCounter,
    output wire [addrBits-1:0] programAddress,
    input  wire [dataBits-1:0] programDataOut,
    output wire                finished,
    // Section: feature I/Os
    input  wire [8:0]          programCounter,
    output wire [7:0]          instruction,
    output wire [8:0]          nextProgramCounter
  );

  // Section: Data path
  reg [7:0] rInstruction;
  assign instruction = rInstruction;

  reg [addrBits-1:0] wProgramAddress;
  assign programAddress = wProgramAddress;

  reg [8:0] rInternalProgramCounter;
  assign nextProgramCounter = rInternalProgramCounter;

  reg [8:0] wActualProgramCounter;
  wire [7:0] instructionFromRamOut = wActualProgramCounter[0] ? programDataOut[7:0] : programDataOut[15:8];

  // Section: Controller

  localparam STATE_PREPARE = 0;
  localparam STATE_DONE    = 1;

  assign finished = rState == STATE_DONE;

  reg rState;

  reg wNextState;
  reg wUpdateInstruction;
  reg wIncrementInternalProgramCounter;

  always @(posedge clk)
    begin
      if (wUpdateInstruction)
        rInstruction <= instructionFromRamOut;

      if (wIncrementInternalProgramCounter)
        rInternalProgramCounter <= rInternalProgramCounter + 1;
      else if (~useInternalProgramCounter)
        rInternalProgramCounter <= programCounter;

      if (!reset)
        rState <= 0;
      else
        rState <= wNextState;
    end

  always @(*)
  begin
    wActualProgramCounter = useInternalProgramCounter ? rInternalProgramCounter : programCounter;
    wProgramAddress = wActualProgramCounter[8:1];
    wNextState = rState + 1;
    wIncrementInternalProgramCounter = rState == STATE_DONE;
    wUpdateInstruction = rState == STATE_DONE;
  end

endmodule
