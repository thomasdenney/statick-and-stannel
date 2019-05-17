`include "defaults.vh"

module Heap_tb();
  // Clock
  reg clk;
  always #1 clk = clk !== 1'b1;

  // Memory
  parameter srcFile = "../programs/hexes/resume_untested.hex";
  parameter dstFile = "zeroes.hex";

  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  reg  [addrBits-1:0] address;
  reg  [dataBits-1:0] dataIn;
  wire [dataBits-1:0] dataOut;
  reg                 readWriteMode;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(srcFile)) heapMemory (
    .clk(clk),
    .address(address),
    .readWriteMode(readWriteMode),
    .dataIn(dataIn),
    .dataOut(dataOut)
  );

  // Test component
  reg reset = 0;
  reg finished;

  reg alloc = 0;
  reg [addrBits-1:0] allocAddress;
  reg free = 0;
  reg [addrBits-1:0] freeAddress;

  Heap #(.addrBits(addrBits), .dataBits(dataBits)) heap0(
    .clk(clk),
    .reset(reset),
    .finished(finished),
    .address(address),
    .readWriteMode(readWriteMode),
    .dataIn(dataIn),
    .dataOut(dataOut),
    .alloc(alloc),
    .allocAddress(allocAddress),
    .free(free),
    .freeAddress(freeAddress)
  );

  task allocTest;
    begin
      alloc <= 1;
      @(posedge finished)
        begin
          alloc       <= 0;
          freeAddress <= allocAddress;
          if (heap0.heapEnd != 1) $error("Should have incremented heap end");
        end
    end
  endtask

  task freeTest;
    begin
      free  <= 1;
      @(posedge finished)
        begin
          free <= 0;
          if (heap0.heapFree != 0) $error("Heap free should be most recently freed address");
          if (heap0.heapEnd != 1) $error("Heap end changed");
        end
    end
  endtask

  task alloc1;
    begin
      alloc <= 1;
      @(posedge finished)
        begin
          alloc <= 0;
          if (allocAddress != 1) $error("Second address to be allocated should be 1");
          if (heap0.heapEnd != 2) $error("Heap end is not 2");
          if (heap0.heapFree != 0) $error("Heap free changed");
        end
    end
  endtask

  task alloc2;
    begin
      alloc <= 1;
      @(posedge finished)
        begin
          alloc <= 0;
          if (allocAddress != 2) $error("Third address to be allocated should be 2");
          if (heap0.heapEnd != 3) $error("Heap end is not 3");
          if (heap0.heapFree != 0) $error("Heap free changed");
        end
    end
  endtask

  task free1;
    begin
      free <= 1;
      freeAddress <= 1;
      @(posedge finished)
        begin
          free <= 0;
          if (heap0.heapFree != 1) $error("Pointer to start of free list should be 1");
          if (heap0.heapEnd != 3) $error("Heap end changed");
          if (heapMemory.ram[1] != 0) $error("1 should point to 0 in free list");
        end
    end
  endtask

  task free2;
    begin
      free <= 1;
      freeAddress <= 2;
      @(posedge finished)
        begin
          free <= 0;
          if (heap0.heapFree != 2) $error("Pointer to start of free list should be 1");
          if (heap0.heapEnd != 3) $error("Heap end changed");
          if (heapMemory.ram[2] != 1) $error("2 should point to 1 in free list");
          if (heapMemory.ram[1] != 0) $error("1 should point to 0 in free list");
        end
    end
  endtask

  task allocWhenHeapEndIsAtMax;
    begin
      heap0.heapEnd <= 8'hFF;
      alloc <= 1;
      @(posedge finished)
        begin
          alloc <= 0;
          if (allocAddress != 2) $error("Should have allocated from head of free list");
          if (heap0.heapFree != 1) $error("Heap free should be 1");
          if (heap0.heapEnd != 8'hFF) $error("Heap end changed");
          if (heapMemory.ram[1] != 0) $error("1 should point to 0 in free list");
        end
    end
  endtask

  initial begin
    $dumpfile("Heap_tb.vcd");
    $dumpvars(0, Heap_tb);
    #3 reset <= 1;
    #2 allocTest;
    #2 freeTest;
    #2 alloc1;
    #2 alloc2;
    #2 free1;
    #2 free2;
    #2 allocWhenHeapEndIsAtMax;
    #2 $finish;
  end
endmodule
