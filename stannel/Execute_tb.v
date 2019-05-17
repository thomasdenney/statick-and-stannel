`include "defaults.vh"
`include "opcodes.vh"
`include "registers.vh"
`include "status.vh"

module Execute_tb();
  localparam addrBits = 8;
  localparam dataBits = 16;

  reg clk;
  always #1 clk <= clk !== 1'b1;

  // NOTE: There is deliberate separation between the RAM and the execution unit here (with the
  // "real" wires) so that the execution unit, in testing, cannot affect the actual contents of RAM.
  // Instead, the behaviour of the execution unit should be tested.
  wire [addrBits-1:0] address;
  wire [dataBits-1:0] dataIn;
  wire [dataBits-1:0] dataInReal;
  wire [dataBits-1:0] dataOut;
  wire                readWriteMode;
  wire                readWriteModeReal = `RAM_READ;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile("execute_tb_data.hex")) ram0(
    .clk(clk),
    .address(address),
    .readWriteMode(readWriteModeReal),
    .dataIn(dataInReal),
    .dataOut(dataOut)
  );

  // Control I/Os for |execute|
  reg reset = 0;
  wire executeFinished;

  // Feature I/Os for |execute|
  reg  [8:0]          expectedNextProgramCounter;
  reg  [addrBits-1:0] stackPointer;
  reg  [addrBits-1:0] callStackPointer;
  reg  [7:0]          instruction;
  reg  [dataBits-1:0] topOfStack1;
  reg  [dataBits-1:0] topOfStack2;
  reg  [dataBits-1:0] topOfStack3;
  reg  [dataBits-1:0] nextTopOfStackOnAlt = {dataBits{1'bx}};
  reg  [8:0]          nextPCOnAlt = 9'bx;

  wire [8:0]          nextProgramCounter;
  wire [addrBits-1:0] nextStackPointer;
  wire [addrBits-1:0] nextCallStackPointer;
  wire [dataBits-1:0] nextTopOfStack1;
  wire [dataBits-1:0] nextTopOfStack2;
  wire [dataBits-1:0] nextTopOfStack3;

  wire       useOutputOfRAM;
  wire [2:0] destinationRegisterOfRamOutput;
  wire       doIOOnNextCycle;
  wire [8:0] ioToDoOnNextCycle;

  wire [1:0] status;

  wire                ioEnabled0;
  wire [addrBits-1:0] ioAddress0;
  wire                ioReadWriteMode0;
  wire [dataBits-1:0] ioWriteValue0;
  wire [2:0]          ioReadRegister0;

  wire pushNextLower;
  wire pushNextUpper;
  wire programCounterIsIncremented;

  reg  [3:0]          message;
  reg  [addrBits-1:0] messageChannel;
  reg  [dataBits-1:0] messageMessage;
  reg  [addrBits-1:0] messageNumWords;
  reg  [8:0]          messageJumpDestination;

  Execute #(.addrBits(addrBits), .dataBits(dataBits)) execute0(
    .clk(clk),
    .reset(reset),
    .enabled(1'b1),
    .finished(executeFinished),
    .addr(address),
    .dataIn(dataIn),
    .ramRW(readWriteMode),
    .expectedNextProgramCounter(expectedNextProgramCounter),
    .stackPointer(stackPointer),
    .callStackPointer(callStackPointer),
    .instruction(instruction),
    .topOfStack1(topOfStack1),
    .topOfStack2(topOfStack2),
    .topOfStack3(topOfStack3),
    .nextTopOfStackOnAlt(nextTopOfStackOnAlt),
    .nextPCOnAlt(nextPCOnAlt),
    .nextProgramCounter(nextProgramCounter),
    .nextStackPointer(nextStackPointer),
    .nextCallStackPointer(nextCallStackPointer),
    .nextTopOfStack1(nextTopOfStack1),
    .nextTopOfStack2(nextTopOfStack2),
    .nextTopOfStack3(nextTopOfStack3),
    .useOutputOfRAM(useOutputOfRAM),
    .destinationRegisterOfRamOutput(destinationRegisterOfRamOutput),
    .pushNextLower(pushNextLower),
    .pushNextUpper(pushNextUpper),
    .programCounterIsIncremented(programCounterIsIncremented),
    .status(status),
    .ioEnabled0(ioEnabled0),
    .ioAddress0(ioAddress0),
    .ioReadWriteMode0(ioReadWriteMode0),
    .ioWriteValue0(ioWriteValue0),
    .ioReadRegister0(ioReadRegister0),
    .loadFlagsFromSavedState(1'b0),
    .savedFlags(4'b0),
    .message(message),
    .messageChannel(messageChannel),
    .messageMessage(messageMessage),
    .messageNumWords(messageNumWords),
    .messageJumpDestination(messageJumpDestination)
  );

  initial begin
    $dumpfile("Execute_tb.vcd");
    $dumpvars(0, Execute_tb);

    #3 reset <= 1;

    // TODO: Verify behaviour of ALU condition codes.

    // Test of ALU +
    begin
      expectedNextProgramCounter = 1;
      stackPointer = 13;
      callStackPointer = 8;
      instruction = { `OP_ALU, `OP_ALU_ADD };
      topOfStack1 = ram0.ram[stackPointer];
      topOfStack2 = ram0.ram[stackPointer + 1];
      topOfStack3 = ram0.ram[stackPointer + 2];

      #4 if (status != `EXEC_STATUS_OK)
        $error("+: Status is not OK");
      if (nextProgramCounter != expectedNextProgramCounter)
        $error("+: Program couter not incremented");
      if (nextTopOfStack1 != topOfStack1 + topOfStack2)
        $error("+: Top of stack after not computed properly.");
      if (nextTopOfStack2 != topOfStack3)
        $error("+: Second of stack not equal to previous third of stack.");
      if (nextStackPointer != stackPointer + 1)
        $error("+: Stack pointer not incremented correctly.");
      if (~useOutputOfRAM)
        $error("+: Expected to use output of RAM");
      if (destinationRegisterOfRamOutput != `REG_S3)
        $error("+: Destination register of RAM is not third of stack.");
      if (dataOut != ram0.ram[nextStackPointer + 2])
        $error("+: RAM out of %d not expected %d", dataOut, ram0.ram[nextStackPointer+2]);
    end

    // Test of ALU not
    begin
      instruction = { `OP_ALU, `OP_ALU_NOT };

      #4 if (status != `EXEC_STATUS_OK)
        $error("~: Status is not OK");
      if (nextProgramCounter != 1)
        $error("~: Program counter not increment.");
      if (nextTopOfStack1 != ~topOfStack1)
        $error("~: Top of stack not notted %d != %d (%d).", nextTopOfStack1, ~topOfStack1, topOfStack1);
      if (nextTopOfStack2 != topOfStack2)
        $error("~: Top of stack 2 not the same.");
      if (nextTopOfStack3 != topOfStack3)
        $error("~: Top of stack 3 not the same.");
      if (nextStackPointer != stackPointer)
        $error("~: Stack pointer changed.");
    end

    // Test of ALU compare
    begin
      instruction = { `OP_ALU, `OP_ALU_COMPARE };

      #4 if (status != `EXEC_STATUS_OK)
        $error("cmp: Status is not OK");
      if (nextProgramCounter != 1)
        $error("cmp: PC not incremented.");
      if (nextTopOfStack1 != topOfStack3)
        $error("cmp: Top of stack not third.");
      if (nextStackPointer != stackPointer + 2)
        $error("cmp: Stack pointer changed.");
      if (~useOutputOfRAM)
        $error("cmp: Expected to use output of RAM");
      if (destinationRegisterOfRamOutput != `REG_S2)
        $error("cmp: Destination register not second of stack.");
      if (dataOut != ram0.ram[nextStackPointer + 1])
        $error("cmp: RAM out of %d not expected %d", dataOut, ram0.ram[nextStackPointer+1]);
      if (~ioEnabled0)
        $error("cmp: Expected to do IO on next cycle");
      if (ioReadWriteMode0 != `RAM_READ)
        $error("cmp: Expected to read on next cycle");
      if (ioReadRegister0 != `REG_S3)
        $error("cmp: Expected destination of IO to be top of stack 3");
      if (ioAddress0 != nextStackPointer + 2)
        $error("cmp: Expected source of IO to be based on stack pointer + 2 (%0d not %0d).", ioAddress0, nextStackPointer + 2);

    end

    // Test of push small constant
    begin
      instruction = { `OP_PUSH, 4'b0111 };

      #4 if (status != `EXEC_STATUS_OK)
        $error("push: Status is not OK");
      if (nextProgramCounter != expectedNextProgramCounter)
        $error("push: PC not incremented.");
      if (nextStackPointer != stackPointer - 1)
        $error("push: stack pointer not decremented.");
      if (nextTopOfStack1 != 7)
        $error("push: next top of stack not expected value of 7.");
      if (nextTopOfStack2 != topOfStack1)
        $error("push: top of stack 2 not expected value.");
      if (nextTopOfStack3 != topOfStack2)
        $error("push: top of stack 3 not expected value.");
      if (address != stackPointer + 2)
        $error("push: execution stage not attempting to write out at sp + 2.");
      if (readWriteMode != `RAM_WRITE)
        $error("push: execution stage not attempting any write out.");
      if (dataIn != topOfStack3)
        $error("push: execution stage not attempting to write out top of stack 3");
    end

    // Test of adding small constant (7)
    begin
      instruction = { `OP_ADD_SMALL, 4'b0111 };
      #4 if (status != `EXEC_STATUS_OK)
        $error("+7: Status is not OK");
      if (nextProgramCounter != expectedNextProgramCounter)
        $error("+7: program counter not incremented.");
      if (nextStackPointer != stackPointer)
        $error("+7: stack pointer changed.");
      if (nextTopOfStack1 != topOfStack1 + 7)
        $error("+7: top of stack not incremented by 7.");
      if (nextTopOfStack2 != topOfStack2)
        $error("+7: top of stack 2 changed.");
      if (nextTopOfStack3 != topOfStack3)
        $error("+7: top of stack 3 changed.");
    end

    // Test of jumping
    begin
      // I'm not testing other conditions here on the basis that they're all tested in alu_tb.v
      instruction = { `OP_JUMP, `OP_CONDITION_ALWAYS };

      #4 if (status != `EXEC_STATUS_OK)
        $error("jump: Status is not OK");
      if (nextProgramCounter != topOfStack1[8:0])
        $error("jump: not atttempted.");
      if (nextStackPointer != stackPointer + 1)
        $error("jump: stack pointer not popped");
      if (nextTopOfStack1 != topOfStack2)
        $error("jump: top of stack 1 not expected value.");
      if (nextTopOfStack2 != topOfStack3)
        $error("jump: top of stack 2 not expected value.");
      if (~useOutputOfRAM)
        $error("jump: expected to use output of RAM.");
      if (address != stackPointer + 3)
        $error("jump: not reading expected address.");
      if (dataOut != ram0.ram[stackPointer + 3])
        $error("jump: read value not expected.");
      if (destinationRegisterOfRamOutput != `REG_S3)
        $error("jump: destination register not top of stack 3");
    end

    // Test of never jumping
    begin
      instruction = { `OP_JUMP, `OP_CONDITION_NEVER };

      #4 if (status != `EXEC_STATUS_OK)
        $error("jump never: Status is not OK");
      if (nextProgramCounter != expectedNextProgramCounter)
        $error("jump never: program counter not incremented as expected.");
      if (nextStackPointer != stackPointer)
        $error("jump never: stack pointer not changed as expected.");
    end

    // Test of drop
    begin
      instruction = { `OP_STACK, `OP_STACK_DROP };

      #4 if (status != `EXEC_STATUS_OK)
        $error("drop: Status is not OK");
      if (nextProgramCounter != expectedNextProgramCounter)
        $error("drop: not attempted.");
      if (nextStackPointer != stackPointer + 1)
        $error("drop: stack pointer not popped");
      if (nextTopOfStack1 != topOfStack2)
        $error("drop: top of stack 1 not expected value.");
      if (nextTopOfStack2 != topOfStack3)
        $error("drop: top of stack 2 not expected value.");
      if (~useOutputOfRAM)
        $error("drop: expected to use output of RAM.");
      if (address != stackPointer + 3)
        $error("drop: not reading expected address.");
      if (dataOut != ram0.ram[stackPointer + 3])
        $error("drop: read value not expected.");
      if (destinationRegisterOfRamOutput != `REG_S3)
        $error("drop: destination register not top of stack 3");
    end

    // Test of dup
    begin
      instruction = { `OP_STACK, `OP_STACK_DUP };
      #4 if (status != `EXEC_STATUS_OK)
        $error("dup: status is not OK");
      if (nextProgramCounter != expectedNextProgramCounter)
        $error("dup: program counter not incremented");
      if (nextStackPointer != stackPointer - 1)
        $error("dup: stack pointer not pushed");
      if (nextTopOfStack1 != topOfStack1 || nextTopOfStack2 != topOfStack1)
        $error("dup: stack top not duplicated");
      if (nextTopOfStack3 != topOfStack2)
        $error("dup: stack top 3 unexpected.");
      if (readWriteMode != `RAM_WRITE)
        $error("dup: not attempting a write.");
      if (address != stackPointer + 2)
        $error("dup: unexpected address");
      if (dataIn != topOfStack3)
        $error("dup: unexpected write value");
    end

    // Test of swap
    begin
      instruction = { `OP_STACK, `OP_STACK_SWAP };
      #4 if (status != `EXEC_STATUS_OK)
        $error("swap: status is not OK.");
      if (nextProgramCounter != expectedNextProgramCounter)
        $error("swap: program counter not incremented");
      if (nextStackPointer != stackPointer)
        $error("swap: stack pointer changed (%0d %0d).", nextStackPointer, stackPointer);
      if (nextTopOfStack1 != topOfStack2 || nextTopOfStack2 != topOfStack1)
        $error("swap: didn't swap values as expected");
      if (nextTopOfStack3 != topOfStack3)
        $error("swap: unexpected manipulation of top of stack 3");
      if (useOutputOfRAM)
        $error("swap: unexpected use of RAM");
      if (readWriteMode != `RAM_READ)
        $error("swap: unexpected write of RAM");
    end

    // Test of rot
    begin
      instruction = { `OP_STACK, `OP_STACK_ROT };
      #4 if (status != `EXEC_STATUS_OK)
        $error("rot: status is not OK.");
      if (nextProgramCounter != expectedNextProgramCounter)
        $error("rot: program counter not incremented");
      if (nextStackPointer != stackPointer)
        $error("rot: stack pointer changed");
      if (nextTopOfStack1 != topOfStack2)
        $error("rot: next top of stack 1 unexpected");
      if (nextTopOfStack2 != topOfStack3)
        $error("rot: next top of stack 2 unexpected");
      if (nextTopOfStack3 != topOfStack1)
        $error("rot: next top of stack 3 unexpected");
      if (useOutputOfRAM)
        $error("rot: unexpected use of RAM output");
      if (readWriteMode != `RAM_READ)
        $error("rot: unexpected write of RAM");
    end

    // Test of tuck
    begin
      instruction = { `OP_STACK, `OP_STACK_TUCK };
      #4 if (status != `EXEC_STATUS_OK)
        $error("tuck: status is not OK.");
      if (nextProgramCounter != expectedNextProgramCounter)
        $error("tuck: program counter not incremented");
      if (nextStackPointer != stackPointer)
        $error("tuck: stack pointer changed");
      if (nextTopOfStack1 != topOfStack3)
        $error("tuck: next top of stack 1 unexpected");
      if (nextTopOfStack2 != topOfStack1)
        $error("tuck: next top of stack 2 unexpected");
      if (nextTopOfStack3 != topOfStack2)
        $error("tuck: next top of stack 3 unexpected");
      if (useOutputOfRAM)
        $error("tuck: unexpected use of RAM output");
      if (readWriteMode != `RAM_READ)
        $error("tuck: unexpected write of RAM");
    end

    // Test of invalid stack instruction
    begin
      instruction = { `OP_STACK, 4'b1111 };
      #4 if (status == `EXEC_STATUS_OK)
        $error("Unexpectedly executed invalid stack instruction OK.");
    end

    // Test of halt instruction
    begin
      instruction = { `OP_PROCESS, `OP_PROCESS_END };
      #4 if (message != `CORE_MESSAGE_HALT)
        $error("halt: did not halt as expected.");
      if (useOutputOfRAM)
        $error("halt: unexpectedly using output of RAM.");
      if (readWriteMode == `RAM_WRITE)
        $error("halt: trying to write.");
    end

    // Test of function call
    begin
      instruction = { `OP_FUNCTION, `OP_FUNCTION_CALL };
      #4 if (status != `EXEC_STATUS_OK)
        $error("call: status not OK.");
      if (nextProgramCounter != topOfStack1[8:0])
        $error("call: didn't jump to call destination.");
      if (nextStackPointer != stackPointer + 1)
        $error("call: didn't pop call destination.");
      if (nextTopOfStack1 != topOfStack2)
        $error("call: top of stack 1 unexpected.");
      if (nextTopOfStack2 != topOfStack3)
        $error("call: top of stack2 unexpected.");
      if (readWriteMode != `RAM_WRITE)
        $error("call: expected to write.");
      if (address != callStackPointer)
        $error("call: unexpected write address.");
      if (dataIn != expectedNextProgramCounter)
        $error("call: unexpected write value.");
      if (~ioEnabled0)
        $error("call: expected to do IO on next cycle.");
      if (ioReadWriteMode0 != `RAM_READ)
        $error("call: read/write action was not read.");
      if (ioReadRegister0 != `REG_S3)
        $error("call: destination of read is not top of stack 3.");
      if (ioAddress0 != nextStackPointer + 2)
        $error("call: source of read is not stack pointer + 2");
    end

    // Test of function return
    begin
      instruction = { `OP_FUNCTION, `OP_FUNCTION_RETURN };
      #4 if (status != `EXEC_STATUS_OK)
        $error("ret: status not OK");
      if (nextCallStackPointer != callStackPointer - 1)
        $error("ret: didn't pop return address");
      if (~useOutputOfRAM)
        $error("ret: expected to use output of RAM");
      if (readWriteMode != `RAM_READ)
        $error("ret: expected to read from RAM");
      if (address != callStackPointer - 1)
        $error("ret: unexpected read address");
      if (destinationRegisterOfRamOutput != `REG_PC)
        $error("ret: expected to output to PC");
    end

    $finish;
  end

endmodule
