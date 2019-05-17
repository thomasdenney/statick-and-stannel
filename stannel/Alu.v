`include "defaults.vh"
`include "opcodes.vh"

// TODO: Does this need a reset?
// TODO: As outputs this will also need all the flags, but I'm not certain how to implement the
// carry and overflow flags yet (zero is obvious)
module Alu #(parameter dataBits = 8) (
    input wire clk,
    input wire reset,
    input wire [dataBits-1:0] aluA,
    input wire [dataBits-1:0] aluB,
    input wire [3:0] func,
    input wire [3:0] condition,
    input wire updateFlags,
    input wire loadFlagsFromSavedState,
    input wire [3:0] savedFlags,
    output wire [dataBits-1:0] aluOut,
    output reg conditionHolds,
    output wire [3:0] exportedAluFlags
  );

  reg carryBit;

  wire wZeroFlag = &(~internalAluOut);
  wire wSignFlag = internalAluOut[dataBits-1];
  wire wCarryFlag = carryBit;

  // Overflow occurs in addition if adding two numbers of the same sign produces a number of a
  // different sign. Overflow occurs in subtraction if the signs are different and the result has
  // the same sign as the thing being subtracted.

  wire wOverflowFlag = additionStyleOverflow ?
    (aluA[dataBits-1] == aluB[dataBits-1] && aluA[dataBits-1] != internalAluOut[dataBits-1]) :
    (aluA[dataBits-1] != aluB[dataBits-1] && aluB[dataBits-1] == internalAluOut[dataBits-1]);

  assign exportedAluFlags = { zeroFlag, signFlag, carryFlag, overflowFlag };

  reg zeroFlag;
  reg signFlag;
  reg carryFlag;
  reg overflowFlag;
  always @(posedge clk) begin
    if (!reset)
      begin
        zeroFlag     <= 0;
        signFlag     <= 0;
        carryFlag    <= 0;
        overflowFlag <= 0;
      end
    else if (updateFlags)
      begin
        if (wUpdateLogicFlags)
          begin
            zeroFlag     <= wZeroFlag;
            signFlag     <= wSignFlag;
          end
        carryFlag    <= wCarryFlag;
        overflowFlag <= wOverflowFlag;
      end
    else if (loadFlagsFromSavedState)
      begin
        zeroFlag     <= savedFlags[3];
        signFlag     <= savedFlags[2];
        carryFlag    <= savedFlags[1];
        overflowFlag <= savedFlags[0];
      end
  end

  reg additionStyleOverflow;
  reg c;
  reg wUpdateLogicFlags;

  wire shouldNegateConditionResult = condition[0];

  // My hope is that this actually just gets implemented as a wire
  reg [dataBits-1:0] internalAluOut;
  always @(*)
  begin
    additionStyleOverflow = 1;
    carryBit = 0;
    wUpdateLogicFlags = func != `OP_ALU_ADD && func != `OP_ALU_SUB;
    case (func)
      `OP_ALU_ADD:
        {carryBit, internalAluOut} = {1'b0,aluA} + {1'b0,aluB};
      `OP_ALU_SUB: begin
        {carryBit, internalAluOut} = {1'b0,aluA} - {1'b0,aluB};
        additionStyleOverflow = 0;
      end
      `OP_ALU_COMPARE: begin
        {carryBit, internalAluOut} = {1'b0,aluA} - {1'b0,aluB};
        additionStyleOverflow = 0;
      end
      `OP_ALU_NOT:
        internalAluOut = ~aluB;
      `OP_ALU_OR:
        internalAluOut = aluA | aluB;
      `OP_ALU_AND:
        internalAluOut = aluA & aluB;
      `OP_ALU_TEST:
        internalAluOut = aluA & aluB;
      `OP_ALU_XOR:
        internalAluOut = aluA ^ aluB;
      default:
        internalAluOut = 0;
    endcase


    case (condition[3:1])
      `OP_CONDITION_ZERO_EQUAL_UPPER_BITS:
        c = zeroFlag;
      `OP_CONDITION_NEGATIVE_UPPER_BITS:
        c = signFlag;
      `OP_CONDITION_UNSIGNED_GREATER_UPPER_BITS:
        c = ~carryFlag & ~zeroFlag;
      `OP_CONDITION_UNSIGNED_GREATER_OR_EQUAL_UPPER_BITS:
        c = ~carryFlag;
      `OP_CONDITION_SIGNED_GREATER_UPPER_BITS:
        c = ~(signFlag ^ overflowFlag) & ~zeroFlag;
      `OP_CONDITION_SIGNED_GREATER_OR_EQUAL_UPPER_BITS:
        c = ~(signFlag ^ overflowFlag);
      `OP_CONDITION_OVERFLOW_UPPER_BITS:
        c = overflowFlag;
      `OP_CONDITION_NEVER_UPPER_BITS:
        c = 0;
    endcase

    conditionHolds = c ^ shouldNegateConditionResult;
  end

  assign aluOut = internalAluOut;

endmodule
