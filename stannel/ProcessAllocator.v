`include "defaults.vh"

module ProcessAllocator #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    input  wire clk,
    input  wire reset,
    input  wire enabled,
    output reg  finished,
    // Feature inputs (should be valid for entire execution)
    input  wire                hasProcessCreate,
    input  wire [addrBits-1:0] wordsToCopy,
    input  wire [8:0]          startProgramCounter,
    input  wire [addrBits-1:0] pidToFree,
    // Memory I/O
    output wire [4:0]          targetMemoryCell,
    input  wire [dataBits-1:0] dataOutForOldStack,
    output wire [addrBits-1:0] addressForOldStack,
    output wire                readWriteForOldStack,
    output wire [dataBits-1:0] dataInForOldStack,
    output wire [dataBits-1:0] dataInForNewStack,
    output wire [addrBits-1:0] addressForNewStack,
    output wire                readWriteForNewStack,
    // Clocked outputs
    output reg  [addrBits-1:0] newPid
  );

  // Memory

  reg [addrBits-1:0] wAddressForOldStack;
  reg                wReadWriteModeForOldStack;
  reg [dataBits-1:0] wDataInForOldStack;

  reg [addrBits-1:0] wAddressForNewStack;
  reg                wReadWriteModeForNewStack;
  reg [dataBits-1:0] wDataInForNewStack;

  assign addressForOldStack   = wCopierEnabled      ? copierReadAddress        : wAddressForOldStack;
  assign readWriteForOldStack = wCopierEnabled      ? copierReadReadWriteMode  : wReadWriteModeForOldStack;
  assign dataInForOldStack    = wDataInForOldStack;

  assign addressForNewStack   = wCopierEnabled      ? copierWriteAddress       : wAddressForNewStack;
  assign dataInForNewStack    = wCopierEnabled      ? copierDataIn             : wDataInForNewStack;
  assign readWriteForNewStack = wCopierEnabled      ? copierWriteReadWriteMode : wReadWriteModeForNewStack;

  // State

  localparam STATE_INIT                   = 4'd0;
  localparam STATE_WAIT_FOR_HEAP_FREE     = 4'd1;
  localparam STATE_READ_OLD_STACK_POINTER = 4'd2;
  localparam STATE_ALLOC                  = 4'd3;
  localparam STATE_WRITE_UPDATED_SP_0     = 4'd4;
  localparam STATE_WRITE_UPDATED_SP_1     = 4'd5;
  localparam STATE_WRITE_SP_0             = 4'd6;
  localparam STATE_WRITE_SP_1             = 4'd7;
  localparam STATE_WRITE_PC_0             = 4'd8;
  localparam STATE_WRITE_PC_1             = 4'd9;
  localparam STATE_COPY                   = 4'd10;

  reg  [3:0]          rState;
  reg  [4:0]          rAllocatedPid;
  reg  [dataBits-1:0] rOldStackPointers;
  wire [addrBits-1:0] oldStackPointer = rOldStackPointers[15:8];
  wire [addrBits-1:0] updatedStackPointer = oldStackPointer + wordsToCopy;
  wire [dataBits-1:0] updatedStackPointers = { updatedStackPointer, rOldStackPointers[7:0] };

  wire [addrBits-1:0] newStackPointer = -wordsToCopy;
  wire [dataBits-1:0] newStackPointers = { newStackPointer, 8'b0 };
  wire [dataBits-1:0] newPCAndAluFlags = { 7'b0, startProgramCounter };

  assign newPid           = { 3'b0, rAllocatedPid };
  assign targetMemoryCell = rAllocatedPid;

  // Signals

  reg [3:0] wNextState;
  reg       wCopierEnabled;
  reg       wFinished;
  reg       wSaveOldStackPointer;
  reg       wSaveAllocatedPid;

  // Sub-components

  reg copierFinished;

  wire [addrBits-1:0] copierReadAddress;
  wire                copierReadReadWriteMode;

  wire [addrBits-1:0] copierWriteAddress;
  wire [dataBits-1:0] copierDataIn;
  wire                copierWriteReadWriteMode;

  Copier #(.addrBits(addrBits), .dataBits(dataBits)) copier(
    .clk                (clk),
    .reset              (wCopierEnabled),
    .finished           (copierFinished),
    .readAddress        (copierReadAddress),
    .readReadWriteMode  (copierReadReadWriteMode),
    .readDataOut        (dataOutForOldStack),
    .writeAddress       (copierWriteAddress),
    .writeReadWriteMode (copierWriteReadWriteMode),
    .writeDataIn        (copierDataIn),
    .startReadAddress   (oldStackPointer),
    .numberOfWordsToCopy(wordsToCopy),
    .startWriteAddress  (newStackPointer)
  );

  reg heapFinished;

  reg                wHeapAlloc;
  // verilator lint_off UNUSED
  reg [addrBits-1:0] heapAllocAddress;
  // verilator lint_on UNUSED
  reg                wHeapFree;
  reg [addrBits-1:0] wHeapFreeAddress;

  reg  [addrBits-1:0] heapAddress;
  reg  [dataBits-1:0] heapDataIn;
  wire [dataBits-1:0] heapDataOut;
  reg                 heapReadWriteMode;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits)) heapRam(
    .clk          (clk),
    .address      (heapAddress),
    .dataIn       (heapDataIn),
    .dataOut      (heapDataOut),
    .readWriteMode(heapReadWriteMode)
  );

  Heap #(.addrBits(addrBits), .dataBits(dataBits), .heapBase(1), .heapMax(`CELL_COUNT)) heap(
    .clk          (clk),
    .reset        (reset),
    .finished     (heapFinished),
    .address      (heapAddress),
    .readWriteMode(heapReadWriteMode),
    .dataOut      (heapDataOut),
    .dataIn       (heapDataIn),
    .alloc        (wHeapAlloc),
    .allocAddress (heapAllocAddress),
    .free         (wHeapFree),
    .freeAddress  (wHeapFreeAddress)
  );


  // Sequential logic

  always @(posedge clk)
    begin
      if (!reset || !enabled)
        begin
          rState <= STATE_INIT;
          rAllocatedPid <= 0;
        end
      else if (enabled)
        begin
          rState <= wNextState;
          finished <= wFinished;

          if (wSaveOldStackPointer)
            rOldStackPointers <= dataOutForOldStack;

          if (wSaveAllocatedPid)
            rAllocatedPid <= heapAllocAddress[4:0];
        end
    end

  // Combinatorial logic

  always @(*)
    begin
      wAddressForOldStack       = {addrBits{1'bx}};
      wReadWriteModeForOldStack = `RAM_READ;
      wDataInForOldStack        = {dataBits{1'bx}};

      wAddressForNewStack       = {addrBits{1'bx}};
      wReadWriteModeForNewStack = `RAM_READ;
      wDataInForNewStack        = {dataBits{1'bx}};

      wHeapAlloc                = 0;
      wHeapFree                 = 0;
      wHeapFreeAddress          = pidToFree;

      wNextState                = rState;
      wCopierEnabled            = 0;
      wFinished                 = 0;
      wSaveOldStackPointer      = 0;
      wSaveAllocatedPid         = 0;

      case (rState)
        STATE_INIT:
          begin
            if (enabled)
              begin
                if (hasProcessCreate)
                  begin
                    wNextState = STATE_READ_OLD_STACK_POINTER;
                    wAddressForOldStack = 0;
                  end
                else
                  begin
                    wHeapFree = 1;
                    wNextState = STATE_WAIT_FOR_HEAP_FREE;
                  end
              end
          end
        STATE_WAIT_FOR_HEAP_FREE:
          begin
            wFinished = heapFinished;
            wHeapFree = ~heapFinished;
          end
        STATE_READ_OLD_STACK_POINTER:
          begin
            wAddressForOldStack = 0;
            wSaveOldStackPointer = 1;
            wNextState = STATE_ALLOC;
          end
        STATE_ALLOC:
          begin
            wHeapAlloc = ~heapFinished;
            if (heapFinished)
              begin
                wSaveAllocatedPid = 1;
                wNextState = STATE_WRITE_UPDATED_SP_0;
              end
          end
        STATE_WRITE_UPDATED_SP_0:
          begin
            wAddressForOldStack       = 0;
            wDataInForOldStack        = updatedStackPointers;
            wReadWriteModeForOldStack = `RAM_WRITE;
            wNextState                = STATE_WRITE_UPDATED_SP_1;
          end
        STATE_WRITE_UPDATED_SP_1:
          begin
            wAddressForOldStack       = 0;
            wDataInForOldStack        = updatedStackPointers;
            wReadWriteModeForOldStack = `RAM_WRITE;
            wNextState                = STATE_WRITE_SP_0;
          end
        STATE_WRITE_SP_0:
          begin
            wAddressForNewStack       = 0;
            wDataInForNewStack        = newStackPointers;
            wReadWriteModeForNewStack = `RAM_WRITE;
            wNextState                = STATE_WRITE_SP_1;
          end
        STATE_WRITE_SP_1:
          begin
            wAddressForNewStack       = 0;
            wDataInForNewStack        = newStackPointers;
            wReadWriteModeForNewStack = `RAM_WRITE;
            wNextState                = STATE_WRITE_PC_0;
          end
        STATE_WRITE_PC_0:
          begin
            wAddressForNewStack       = 1;
            wDataInForNewStack        = newPCAndAluFlags;
            wReadWriteModeForNewStack = `RAM_WRITE;
            wNextState                = STATE_WRITE_PC_1;
          end
        STATE_WRITE_PC_1:
          begin
            wAddressForNewStack       = 1;
            wDataInForNewStack        = newPCAndAluFlags;
            wReadWriteModeForNewStack = `RAM_WRITE;
            wNextState                = STATE_COPY;
          end
        STATE_COPY:
          begin
            wCopierEnabled = ~copierFinished;
            if (copierFinished)
              begin
                wFinished = 1;
              end
          end
        default:
          begin
          end
      endcase
    end

endmodule
