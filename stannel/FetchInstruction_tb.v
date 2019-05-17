`include "defaults.vh"

module FetchInstruction_tb();
  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  reg reset = 0;

  reg clk;
  always #1 clk <= clk !== 1;

  wire [addrBits-1:0] address;
  wire [dataBits-1:0] dataIn;
  wire [dataBits-1:0] dataOut;
  wire                rw = `RAM_READ;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile("fetch_test_data.hex")) ram0 (
    .clk(clk),
    .address(address),
    .readWriteMode(rw),
    .dataIn(dataIn),
    .dataOut(dataOut)
  );

  wire fetchWillFinish;

  reg useInternalProgramCounter;
  reg [8:0] programCounter;

  wire [7:0] instruction;
  wire [8:0] nextProgramCounter;

  FetchInstruction #(.addrBits(addrBits), .dataBits(dataBits)) fetch0 (
    .clk(clk),
    .reset(reset),
    .useInternalProgramCounter(useInternalProgramCounter),
    .programCounter(programCounter),
    .programAddress(address),
    .programDataOut(dataOut),
    .nextProgramCounter(nextProgramCounter),
    .instruction(instruction)
  );

  initial begin
    $dumpfile("FetchInstruction_tb.vcd");
    $dumpvars(0, FetchInstruction_tb);

    programCounter = 0;
    useInternalProgramCounter = 0;
    #4 reset <= 1;

    #4 if (instruction != 8'h00) $error("Instruction at 0 should be 00");
       if (nextProgramCounter != 1) $error("Next program counter not 1");

    useInternalProgramCounter = 1;

    #4 if (instruction != 8'h01) $error("Instruction at 1 should be 01");
       if (nextProgramCounter != 2) $error("Next program counter not 2");

    #4 if (instruction != 8'h02) $error("Instruction at 2 should be 02");
       if (nextProgramCounter != 3) $error("Next program counter not 3");

    useInternalProgramCounter = 0;
    programCounter = 14;

    #4 if (instruction != 8'h0E) $error("Instruction at 14 should be 0E");
       if (nextProgramCounter != 15) $error("Next program counter should be 15");

    #4 $finish;
  end

endmodule
