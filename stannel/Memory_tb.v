`include "defaults.vh"

// verilator lint_off STMTDLY
module Memory_tb();
  reg clk;
  always #1 clk = clk !== 1'b1;

  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  reg [addrBits-1:0] address0 = {addrBits{1'bx}};
  reg [addrBits-1:0] address1 = {addrBits{1'bx}};
  reg [addrBits-1:0] address2 = {addrBits{1'bx}};
  reg [addrBits-1:0] address3 = {addrBits{1'bx}};

  reg readWriteMode0 = `RAM_READ;
  reg readWriteMode1 = `RAM_READ;
  reg readWriteMode2 = `RAM_READ;
  reg readWriteMode3 = `RAM_READ;

  reg [dataBits-1:0] dataIn0 = {dataBits{1'bx}};
  reg [dataBits-1:0] dataIn1 = {dataBits{1'bx}};
  reg [dataBits-1:0] dataIn2 = {dataBits{1'bx}};
  reg [dataBits-1:0] dataIn3 = {dataBits{1'bx}};

  wire [dataBits-1:0] dataOut0;
  wire [dataBits-1:0] dataOut1;
  wire [dataBits-1:0] dataOut2;
  wire [dataBits-1:0] dataOut3;

  reg [1:0] cell0ToUser = 2'bx;
  reg [1:0] cell1ToUser = 2'bx;

  MemoryController2x4 #(.addrBits(addrBits), .dataBits(dataBits)) mem(
    address0,
    address1,
    address2,
    address3,
    readWriteMode0,
    readWriteMode1,
    readWriteMode2,
    readWriteMode3,
    dataIn0,
    dataIn1,
    dataIn2,
    dataIn3,
    dataOut0,
    dataOut1,
    dataOut2,
    dataOut3,
    cell0ToUser,
    cell1ToUser,
    clk
  );

  initial
    begin
      $dumpfile("Memory_tb.vcd");
      $dumpvars(0, Memory_tb);

      address0       = 0;
      readWriteMode0 = `RAM_WRITE;
      dataIn0        = 16'hFAB0;

      address1       = 0;
      readWriteMode1 = `RAM_WRITE;
      dataIn1        = 16'hFAB1;

      address2       = 0;
      readWriteMode2 = `RAM_WRITE;
      dataIn2        = 16'hFAB2;

      address3       = 0;
      readWriteMode3 = `RAM_WRITE;
      dataIn3        = 16'hFAB3;

      cell0ToUser = 0;
      cell1ToUser = 1;

      // Verify that general IO works

      #2 readWriteMode0 = `RAM_READ;
         readWriteMode1 = `RAM_READ;

      #2 if (dataOut0 != dataIn0) $error("U0,C0: %0d != %0d", dataOut0, dataIn0);
         if (dataOut1 != dataIn1) $error("U1,C1: %0d != %0d", dataOut1, dataIn1);

      #2 cell0ToUser = 2;
         cell1ToUser = 3;

      #2 readWriteMode2 = `RAM_READ;
         readWriteMode3 = `RAM_READ;

      #2 if (dataOut2 != dataIn2) $error("U2,C0: %0d != %0d", dataOut2, dataIn2);
         if (dataOut3 != dataIn3) $error("U3,C1: %0d != %0d", dataOut3, dataIn3);


      // Parallel IO
      #2 address0 =        1;
         dataIn0  =        16'hC0FE;
         readWriteMode0 = `RAM_WRITE;

         cell0ToUser = 0;
         cell1ToUser = 0;

      #2 if (mem.cell0.ram[address0] != dataIn0) $error("U0,C0: %0d != %0d", mem.cell0.ram[address0], dataIn0);
         if (mem.cell1.ram[address0] != dataIn0) $error("U0,C1: %0d != %0d", mem.cell1.ram[address0], dataIn0);

      #2 $finish;
    end

endmodule

// verilator lint_on STMTDLY
