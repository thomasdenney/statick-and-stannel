`include "defaults.vh"

module ResumeState_tb();
  parameter romFile = "../programs/hexes/resume_untested.hex";
  parameter ramFile = "resume.hex";

  reg clk;
  always #1 clk = clk !== 1'b1;

  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;
  localparam ramSize = 2 ** addrBits;

  wire [addrBits-1:0] address;
  wire [dataBits-1:0] dataIn;
  wire [dataBits-1:0] dataOut;
  wire                rw;

  wire [addrBits-1:0] programAddress;
  wire [dataBits-1:0] programDataOut;
  wire [dataBits-1:0] programDataIn;
  wire                programReadWriteMode = `RAM_READ;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(romFile)) rom0 (
    .clk(clk),
    .address(programAddress),
    .readWriteMode(programReadWriteMode),
    .dataIn(programDataIn),
    .dataOut(programDataOut)
  );

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(ramFile)) ram0 (
    .clk(clk),
    .address(address),
    .readWriteMode(rw),
    .dataIn(dataIn),
    .dataOut(dataOut)
  );

  reg reset = 0;
  reg enabled = 0;
  wire finished;

  reg [2:0]          processorMessage = `PROCESSOR_MESSAGE_NONE;
  reg [dataBits-1:0] processorMessagePushValue = {dataBits{1'bx}};
  reg [8:0]          processorMessageJumpDestination = 9'bx;

  reg  [3:0]          coreMessage;
  reg  [addrBits-1:0] coreMessageChannel;
  reg  [dataBits-1:0] coreMessageMessage;
  reg  [addrBits-1:0] coreMessageNumWords;
  reg  [8:0]          coreMessageJumpDestination;

  reg resumeFromMemory = 1;

  reg readyToReceive;
  reg executing;

  Core #(.addrBits(addrBits), .dataBits(dataBits)) core (
    .clk(clk),
    .reset(reset),
    .programAddress(programAddress),
    .programDataOut(programDataOut),
    .ramDataOut(dataOut),
    .ramReadWriteMode(rw),
    .ramDataIn(dataIn),
    .ramAddress(address),
    .processorMessage(processorMessage),
    .processorMessagePushValue(processorMessagePushValue),
    .processorMessageJumpDestination(processorMessageJumpDestination),
    .coreMessage(coreMessage),
    .coreMessageChannel(coreMessageChannel),
    .coreMessageMessage(coreMessageMessage),
    .coreMessageNumWords(coreMessageNumWords),
    .coreMessageJumpDestination(coreMessageJumpDestination),
    .readyToReceive(readyToReceive),
    .executing(executing)
  );

  initial begin
    $dumpfile("ResumeState_tb.vcd");
    $dumpvars(0, ResumeState_tb);
    // Deliberately waiting a cycle to make it really obvious when the start happens and what
    // the result is after the reset occurs.
    #1 reset <= 1;
    #3 processorMessage <= `PROCESSOR_MESSAGE_RESUME_AND_WAIT;
    #2 processorMessage <= `PROCESSOR_MESSAGE_RESUME;
    #11 processorMessage <= `PROCESSOR_MESSAGE_NONE;
    #14 begin
        if (core.programCounter != 1) $error("Program counter");
        if (core.stackPointer != 8'hFD) $error("Stack pointer");
        if (core.callStackPointer != 4) $error("Call stack pointer");
        if (core.topOfStack1 != 7) $error("Top of stack 1");
        if (core.topOfStack2 != 42) $error("Top of stack 2");
        $finish;
      end
  end
endmodule
