`include "defaults.vh"
`include "opcodes.vh"

`define STRINGIFY(x) `"x`"

module Alu_tb();
  localparam dataBits = 8;
  reg[dataBits-1:0] aluA = 8'b01110100; // 64 + 32 + 16 + 4 = 116
  reg[dataBits-1:0] aluB = 8'b00001100; // 8 + 4 = 12
  reg[3:0] aluFunc;
  reg[3:0] condition = `OP_CONDITION_ALWAYS;
  wire[dataBits-1:0] aluOut;
  reg conditionHolds;
  reg reset = 0;

  reg clk = 0;
  always #1 clk <= ~clk;

  reg updateFlags = 0;

  Alu #(.dataBits(dataBits)) alu(
    .clk(clk),
    .reset(reset),
    .aluA(aluA),
    .aluB(aluB),
    .func(aluFunc),
    .condition(condition),
    .updateFlags(updateFlags),
    .aluOut(aluOut),
    .conditionHolds(conditionHolds),
    .loadFlagsFromSavedState(1'b0),
    .savedFlags(4'b0)
  );

  task check;
    input[dataBits-1:0] a, b;
    input[3:0] cond;
    input e;
    input[1024*8-1:0] s;
    begin
      aluA <= a;
      aluB <= b;
      condition <= cond;
      updateFlags <= 1;
      #2 updateFlags <= 0;
      if (conditionHolds != e)
        begin
          $error("[FAIL]\t%0d %0s %0d (expected %d, got %d, ZF=%0d,OF=%0d,SF=%0d,CF=%0d)",
            a, s, b, e, conditionHolds,
            alu.zeroFlag, alu.overflowFlag, alu.signFlag, alu.carryFlag);
          $finish;
        end
    end
  endtask

  initial begin
    $dumpfile("Alu_tb.vcd");
    $dumpvars(0, Alu_tb);

    #1 reset <= 1;
    // Arithmetic tests

    #1 aluFunc <= `OP_ALU_ADD;
    if (aluOut != 128) $error("%d != 116 + 12", aluOut);
    aluFunc <= `OP_ALU_SUB;
    if (aluOut != 104) $error("%d != 116 - 12", aluOut);
    aluFunc <= `OP_ALU_NOT;
    if (aluOut != 139) $error("%d != ~116", aluOut);
    aluFunc <= `OP_ALU_OR;
    if (aluOut != 124) $error("%d != 116 | 12", aluOut);
    aluFunc <= `OP_ALU_AND;
    if (aluOut != 4) $error("%d != 116 & 12", aluOut);
    aluFunc <= `OP_ALU_XOR;
    if (aluOut != 120) $error("%d != 116 ^ 12", aluOut);

    // Logic tests
    aluFunc <= `OP_ALU_COMPARE;

    check(255, 255, `OP_CONDITION_ZERO_EQUAL, 1, "==");
    check(255, 253, `OP_CONDITION_ZERO_EQUAL, 0, "==");
    check(255, 255, `OP_CONDITION_NOT_ZERO_NOT_EQUAL, 0, "!=");
    check(255, 254, `OP_CONDITION_NOT_ZERO_NOT_EQUAL, 1, "!=");
    check(000, 001, `OP_CONDITION_NEGATIVE, 1, "-");
    check(002, 001, `OP_CONDITION_NEGATIVE, 0, "-");
    check(127, 126, `OP_CONDITION_UNSIGNED_GREATER, 1, ">u");
    check(126, 127, `OP_CONDITION_UNSIGNED_GREATER, 0, ">u");
    check(225, 031, `OP_CONDITION_UNSIGNED_GREATER, 1, ">u");
    check(031, 225, `OP_CONDITION_UNSIGNED_GREATER, 0, ">u");
    check(126, 127, `OP_CONDITION_UNSIGNED_LESS_OR_EQUAL, 1, "<=u");
    check(127, 126, `OP_CONDITION_UNSIGNED_LESS_OR_EQUAL, 0, "<=u");
    check(126, 126, `OP_CONDITION_UNSIGNED_LESS_OR_EQUAL, 1, "<=u");
    check(127, 126, `OP_CONDITION_UNSIGNED_GREATER_OR_EQUAL, 1, ">=u");
    check(127, 127, `OP_CONDITION_UNSIGNED_GREATER_OR_EQUAL, 1, ">=u");
    check(126, 127, `OP_CONDITION_UNSIGNED_GREATER_OR_EQUAL, 0, ">=u");
    check(126, 127, `OP_CONDITION_UNSIGNED_LESS, 1, "<u");
    check(126, 126, `OP_CONDITION_UNSIGNED_LESS, 0, "<u");
    check(127, 126, `OP_CONDITION_UNSIGNED_LESS, 0, "<u");
    check(100, 050, `OP_CONDITION_SIGNED_GREATER, 1, ">s");
    check(100, 100, `OP_CONDITION_SIGNED_GREATER, 0, ">s");
    check(050, 100, `OP_CONDITION_SIGNED_GREATER, 0, ">s");
    check(150, 175, `OP_CONDITION_SIGNED_GREATER, 0, ">s");
    check(175, 150, `OP_CONDITION_SIGNED_GREATER, 1, ">s");
    check(200, 010, `OP_CONDITION_SIGNED_GREATER, 0, ">s");
    check(001, 002, `OP_CONDITION_SIGNED_LESS_OR_EQUAL, 1, "<=s");
    check(127, 127, `OP_CONDITION_SIGNED_LESS_OR_EQUAL, 1, "<=s");
    check(128, 127, `OP_CONDITION_SIGNED_LESS_OR_EQUAL, 1, "<=s");
    check(128, 128, `OP_CONDITION_SIGNED_LESS_OR_EQUAL, 1, "<=s");
    check(100, 050, `OP_CONDITION_SIGNED_GREATER_OR_EQUAL, 1, ">=s");
    check(050, 100, `OP_CONDITION_SIGNED_GREATER_OR_EQUAL, 0, ">=s");
    check(128, 128, `OP_CONDITION_SIGNED_GREATER_OR_EQUAL, 1, ">=s");
    check(130, 150, `OP_CONDITION_SIGNED_GREATER_OR_EQUAL, 0, ">=s");
    check(150, 130, `OP_CONDITION_SIGNED_GREATER_OR_EQUAL, 1, ">=s");
    check(128, 127, `OP_CONDITION_SIGNED_LESS, 1, "<s");
    check(127, 128, `OP_CONDITION_SIGNED_LESS, 0, "<s");
    check(100, 050, `OP_CONDITION_SIGNED_LESS, 0, "<s");
    check(100, 100, `OP_CONDITION_SIGNED_LESS, 0, "<s");
    check(050, 100, `OP_CONDITION_SIGNED_LESS, 1, "<s");
    check(150, 175, `OP_CONDITION_SIGNED_LESS, 1, "<s");
    check(175, 150, `OP_CONDITION_SIGNED_LESS, 0, "<s");
    check(200, 010, `OP_CONDITION_SIGNED_LESS, 1, "<s");

    aluFunc = `OP_ALU_ADD;
    check(127, 127, `OP_CONDITION_OVERFLOW, 1, "+overflow");
    check(10, 10, `OP_CONDITION_OVERFLOW, 0, "+overflow");
    check(127, 127, `OP_CONDITION_NO_OVERFLOW, 0, "+overflow");
    check(10, 10, `OP_CONDITION_NO_OVERFLOW, 1, "+overflow");

    check(0, 0, `OP_CONDITION_ALWAYS, 1, "always");
    check(0, 0, `OP_CONDITION_NEVER, 0, "never");

    $finish;
  end
endmodule
