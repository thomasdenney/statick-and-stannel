`include "defaults.vh"

module SoC_tb();
  // WARNING: You must change this in Makefile
  parameter romFile = "../programs/hexes/halt.hex";
  // Leave this as FF to ensure everything is sent
  parameter maxAddressToSend = 8'hFF;

  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;
  localparam ramSize = 2 ** addrBits;

  // Simulating at a virtual clock speed of 115200 Hz * 2
  localparam CYCLES = 2;

  // Double because these need to be SoC clock cycles, which are double the length of RAM
  // clock cycles, which are equal to twice the tick rate of the simulation.
  localparam baud = CYCLES * 2;
  localparam bitrate = baud << 1;
  localparam frame = bitrate * 11;
  localparam frameWait = bitrate * 4;
  localparam byteWait = frameWait * 2;

  reg i;
  task sendByte;
    input [7:0] in;
    begin
      #bitrate rx <= 0;
      #bitrate rx <= in[0];
      #bitrate rx <= in[1];
      #bitrate rx <= in[2];
      #bitrate rx <= in[3];
      #bitrate rx <= in[4];
      #bitrate rx <= in[5];
      #bitrate rx <= in[6];
      #bitrate rx <= in[7];
      #bitrate rx <= 1;
      #bitrate rx <= 1;
    end
  endtask

  reg clk;
  always #2 clk = (clk !== 1'b1);

  wire tx;
  reg rx = 1;

  wire [2:0] status;

  SoC #(.clockRate(115200 * CYCLES)) soc(
    .clk(clk),
    .tx(tx),
    .rx(rx),
    .status(status)
  );

  reg reset = 0;

  wire rcv;
  wire [7:0] uartReceived;

  UartRx #(.clockRate(115200 * CYCLES)) uartRx(
    .clk(clk),
    .reset(reset),
    .rx(tx),
    .rcv(rcv),
    .data(uartReceived)
  );

  reg [dataBits-1:0] rom[0:ramSize-1];

  reg [7:0] top1High;
  reg [7:0] top1Low;
  reg [7:0] top2High;
  reg [7:0] top2Low;
  reg [7:0] top3High;
  reg [7:0] top3Low;
  reg [7:0] pcHigh;
  reg [7:0] pcLow;
  reg [7:0] sp;
  reg [7:0] ccHigh;
  reg [7:0] ccLow;
  reg [7:0] csp;

  task dumpInstructions;
    begin
      $write("[PROGRAM]:\t%02h:%02h", soc.instructionMemory.cell0.ram[0][15:8], soc.instructionMemory.cell0.ram[0][7:0]);
      for (int j = 1; j < 256; ++j) $write(":%02h:%02h", soc.instructionMemory.cell0.ram[j][15:8], soc.instructionMemory.cell0.ram[j][7:0]);
      $write("\n");
    end
  endtask

  task receiveCore;
    begin
      for (int i = 1; i < 512; ++i)
        @(posedge rcv) $write("%02h:", uartReceived);
      @(posedge rcv) $write("%02h\n", uartReceived);
    end
  endtask

  initial begin
    $dumpfile("SoC_tb.vcd");
    $dumpvars(0, SoC_tb);
    $readmemh(romFile, rom);

    #3 reset <= 1;
    #byteWait sendByte(maxAddressToSend);

    for (int i = 0; i <= maxAddressToSend; ++i)
      begin
        #byteWait sendByte(rom[i][15:8]);
        #byteWait sendByte(rom[i][7:0]);
      end

    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;
    receiveCore;

    `define checkRam(port, c) \
      begin \
        for (int i = 0; i < 2 ** `ADDRESS_BITS; ++i) \
          if (port.ram[i] != 0) $error("cell%0d[%0d] == %0d != 0", c, i, port.ram[i]); \
      end;

    // Verify that the memory is zeroed afterwards
    `checkRam(soc.stackMemory.cell0, 0);
    `checkRam(soc.stackMemory.cell1, 1);
    `checkRam(soc.stackMemory.cell2, 2);
    `checkRam(soc.stackMemory.cell3, 3);
    `checkRam(soc.stackMemory.cell4, 4);
    `checkRam(soc.stackMemory.cell5, 5);
    `checkRam(soc.stackMemory.cell6, 6);
    `checkRam(soc.stackMemory.cell7, 7);
    `checkRam(soc.stackMemory.cell8, 8);
    `checkRam(soc.stackMemory.cell9, 9);
    `checkRam(soc.stackMemory.cell10, 10);
    `checkRam(soc.stackMemory.cell11, 11);
    `checkRam(soc.stackMemory.cell12, 12);
    `checkRam(soc.stackMemory.cell13, 13);
    `checkRam(soc.stackMemory.cell14, 14);
    `checkRam(soc.stackMemory.cell15, 15);
    `checkRam(soc.stackMemory.cell16, 16);

    $finish;
  end
endmodule
