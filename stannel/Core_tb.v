`include "defaults.vh"

module Core_tb();
  parameter romFile = "../programs/hexes/add.hex";
  parameter zeroFile = "zeroes.hex";

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

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(zeroFile)) ram0 (
    .clk(clk),
    .address(address),
    .readWriteMode(rw),
    .dataIn(dataIn),
    .dataOut(dataOut)
  );

  reg reset = 0;
  reg enabled = 0;

  reg [2:0]          processorMessage = `PROCESSOR_MESSAGE_NONE;
  reg [dataBits-1:0] processorMessagePushValue = {dataBits{1'bx}};
  reg [8:0]          processorMessageJumpDestination = 9'bx;

  reg  [3:0]          coreMessage;
  reg  [addrBits-1:0] coreMessageChannel;
  reg  [dataBits-1:0] coreMessageMessage;
  reg  [addrBits-1:0] coreMessageNumWords;
  reg  [8:0]          coreMessageJumpDestination;

  reg readyToReceive;
  reg executing;

  Core #(.addrBits(addrBits), .dataBits(dataBits)) core0 (
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

  task dump_ram;
    begin
      // Halts the simulation
      // Divide by two because our clock has positive edges every two cycles in this simulation
      $display("%0d cycles", $time / 2);
      // Prints the stack and registers
      $write("Core state:\t%0d\n", core0.state);
      $write("SP:\t%0d\tCSP:\t%0d\tPC:\t%0d\t", core0.stackPointer, core0.callStackPointer, core0.programCounter);
      $write("ZF=%0d SF=%0d OF=%0d CF=%0d\t",
        core0.execute0.alu0.zeroFlag,
        core0.execute0.alu0.signFlag,
        core0.execute0.alu0.overflowFlag,
        core0.execute0.alu0.carryFlag);
      $write("Stack: ");
      if (core0.stackPointer > 0 && core0.stackPointer < ramSize) begin
        $write("%0d", ram0.ram[core0.stackPointer]);
        for (int i = core0.stackPointer + 1; i < ramSize; ++i) $write(" %0d", ram0.ram[i]);
      end
      $write("\n");
      // Prints the full hex for RAM
      for (int i = 0; i < ramSize; ++i) begin
        $write("%x", ram0.ram[i]);
        if (i != ramSize-1) $write(":");
        else $write("\n");
      end

      if ($isunknown(core0.programCounter) || (coreMessage == `CORE_MESSAGE_HALT && readyToReceive)) $finish;
    end
  endtask

  initial begin
    $dumpfile("Core_tb.vcd");
    $dumpvars(0, Core_tb);
    // Deliberately waiting a cycle to make it really obvious when the start happens and what
    // the result is after the reset occurs.
    #3 reset <= 1;
    #1 processorMessage <= `PROCESSOR_MESSAGE_RESUME_AND_WAIT;
    #1 processorMessage <= `PROCESSOR_MESSAGE_RESUME;
    // This is exactly the correct number of cycles
    #12 processorMessage <= `PROCESSOR_MESSAGE_NONE;

    // This will print on every fetch
    #4 while (1) begin
      // Every 2 cycles because the clock only has positive edges every two cycles
      #4 dump_ram();
    end
  end
endmodule
