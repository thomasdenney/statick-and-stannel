`include "defaults.vh"
`include "opcodes.vh"
`include "registers.vh"
`include "status.vh"

module Io_tb();
  localparam addrBits = 8;
  localparam dataBits = 16;

  reg clk = 1;
  always #1 clk <= ~clk;

  // NOTE: There is deliberate separation between the RAM and the I/O unit here (with the
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

  // Control I/Os for |IO|
  reg reset = 0;

  // Feature I/Os for |IO|
  reg                readWriteAction;
  reg [addrBits-1:0] readOrWriteAddress;
  reg [dataBits-1:0] writeValue;
  reg [2:0]          destinationRegister;

  reg  [8:0]          programCounter   = 0;
  reg  [addrBits-1:0] stackPointer     = 13;
  reg  [addrBits-1:0] callStackPointer = 8;
  reg  [dataBits-1:0] topOfStack1;
  reg  [dataBits-1:0] topOfStack2;
  reg  [dataBits-1:0] topOfStack3;

  wire [8:0]          nextProgramCounter;
  wire [addrBits-1:0] nextStackPointer;
  wire [addrBits-1:0] nextCallStackPointer;
  wire [dataBits-1:0] nextTopOfStack1;
  wire [dataBits-1:0] nextTopOfStack2;
  wire [dataBits-1:0] nextTopOfStack3;

  Io #(.addrBits(addrBits), .dataBits(dataBits)) io0(
    .clk(clk),
    .reset(reset),
    .dataOut(dataOut),
    .addr(address),
    .dataIn(dataIn),
    .ramRW(readWriteMode),
    .readWriteAction(readWriteAction),
    .readOrWriteAddress(readOrWriteAddress),
    .writeValue(writeValue),
    .destinationRegister(destinationRegister),
    .programCounter(programCounter),
    .stackPointer(stackPointer),
    .callStackPointer(callStackPointer),
    .topOfStack1(topOfStack1),
    .topOfStack2(topOfStack2),
    .topOfStack3(topOfStack3),
    .nextProgramCounter(nextProgramCounter),
    .nextStackPointer(nextStackPointer),
    .nextCallStackPointer(nextCallStackPointer),
    .nextTopOfStack1(nextTopOfStack1),
    .nextTopOfStack2(nextTopOfStack2),
    .nextTopOfStack3(nextTopOfStack3)
  );

  initial begin
    $dumpfile("Io_tb.vcd");
    $dumpvars(0, Io_tb);

    #4 begin
      reset = 0;
      // Read sp + 0 to register s1
      readWriteAction = `RAM_READ;
      readOrWriteAddress = stackPointer;
      destinationRegister = `REG_S1;
      #4 reset = 1;

      #4 if (nextTopOfStack1 != ram0.ram[stackPointer + 0])
        $error("readSp1: top of stack not updated as expected");
      if (readWriteMode != `RAM_READ)
        $error("readSp1: didn't perform read");
      if (address != stackPointer + 0)
        $error("readSp1: didn't perform read at expected address");

      if (nextProgramCounter != programCounter)
        $error("readSp1: PC changed");
      if (nextStackPointer != stackPointer)
        $error("readSp1: SP changed");
      if (nextCallStackPointer != callStackPointer)
        $error("readSp1: CSP changed");
      if (nextTopOfStack2 != topOfStack2)
        $error("readSp1: stack top 2 changed");
      if (nextTopOfStack3 != topOfStack3)
        $error("readSp1: stack top 3 changed");
    end

    #4 begin
      reset = 0;
      readWriteAction = `RAM_READ;
      readOrWriteAddress = stackPointer + 1;
      destinationRegister = `REG_S2;
      #4 reset = 1;

      #4 if (nextTopOfStack2 != ram0.ram[stackPointer + 1])
        $error("readSp2: top of stack 2 not updated as expected.");
      if (readWriteMode != `RAM_READ)
        $error("readSp2: didn't perform read");
      if (address != stackPointer + 1)
        $error("readSp2: read not from expected address");
      // Unlike the previous test, I'm going to assume that no other values are updated (as that
      // would be weird, and the code is not structured in such a way that that could happen).
    end

    #4 begin
      reset = 0;
      readWriteAction = `RAM_READ;
      readOrWriteAddress = stackPointer + 2;
      destinationRegister = `REG_S3;
      #4 reset = 1;

      #4 if (nextTopOfStack3 != ram0.ram[stackPointer + 2])
        $error("readSp3: top of stack 3 not updated as expected.");
      if (readWriteMode != `RAM_READ)
        $error("readSp3: didn't perform read");
      if (address != stackPointer + 2)
        $error("readSp3: read not from expected address");
    end

    #4 begin
      reset = 0;
      readWriteAction = `RAM_WRITE;
      readOrWriteAddress = stackPointer + 2;
      writeValue = topOfStack3;
      #4 reset = 1;

      #4 if (readWriteMode != `RAM_WRITE)
        $error("writeSp3: not writing as expected");
      if (dataIn != topOfStack3)
        $error("writeSp3: not writing top of stack 3 as expected.");
      if (address != stackPointer + 2)
        $error("writeSp3: not writing to stack pointer + 2 as expected.");
    end

    #4 $finish;
  end

endmodule
