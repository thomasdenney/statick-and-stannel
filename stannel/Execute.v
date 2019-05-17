`include "defaults.vh"
`include "messages.vh"
`include "opcodes.vh"
`include "registers.vh"
`include "status.vh"

// The outputs of this module need registering on clock cycles
module Execute #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS, parameter cpuId = 0) (
    // SECTION: operational I/Os
    input  wire                clk,
    input  wire                enabled,
    input  wire                reset, // TODO: Verify if this is actually necessary?
    output wire                finished,
    output wire [addrBits-1:0] addr,
    output wire [dataBits-1:0] dataIn,
    output wire                ramRW,
    // SECTION: feature I/Os
    // TODO: Ensure that the top few of stack are actually just kept in registers
    input  wire [8:0]          expectedNextProgramCounter,
    input  wire [addrBits-1:0] stackPointer,
    input  wire [addrBits-1:0] callStackPointer,
    input  wire [7:0]          instruction,
    input  wire [dataBits-1:0] topOfStack1,
    input  wire [dataBits-1:0] topOfStack2,
    input  wire [dataBits-1:0] topOfStack3,
    input  wire [dataBits-1:0] nextTopOfStackOnAlt,
    input  wire [8:0]          nextPCOnAlt,
    input  wire                loadFlagsFromSavedState,
    input  wire [3:0]          savedFlags,
    output wire [8:0]          nextProgramCounter,
    output wire [addrBits-1:0] nextStackPointer,
    output wire [addrBits-1:0] nextCallStackPointer,
    output wire [dataBits-1:0] nextTopOfStack1,
    output wire [dataBits-1:0] nextTopOfStack2,
    output wire [dataBits-1:0] nextTopOfStack3,
    output wire                useOutputOfRAM,
    output wire [2:0]          destinationRegisterOfRamOutput,
    output wire                pushNextLower,
    output wire                pushNextUpper,
    output wire                programCounterIsIncremented,
    output wire [1:0]          status,
    // First cycle of I/O
    output wire                ioEnabled0,
    output wire [addrBits-1:0] ioAddress0,
    output wire                ioReadWriteMode0,
    output wire [dataBits-1:0] ioWriteValue0,
    output wire [2:0]          ioReadRegister0,
    // To simplify logic, just reload rather than attempting complex I/O
    output wire                needsFullFetch,
    output wire [3:0]          exportedAluFlags,
    // Communication with Processor
    output reg  [3:0]          message,
    output reg  [addrBits-1:0] messageChannel,
    output reg  [dataBits-1:0] messageMessage,
    output reg  [addrBits-1:0] messageNumWords,
    output reg  [8:0]          messageJumpDestination
  );

  // SECTION: Data path

  // Must stay in the execution stage for two cycles
  // TODO: A later design could avoid staying in the execution stage
  reg state;
  always @(posedge clk)
    if (!reset || !enabled)
      state <= 0;
    else
      state <= state + 1;
  assign finished = state == 1;

  reg [addrBits-1:0] rAddr;
  reg                rRamRW;
  reg [dataBits-1:0] rDataIn;

  assign addr  = rAddr;
  assign ramRW = rRamRW;
  assign dataIn = rDataIn;

  reg       rUseOutputOfRAM;
  reg [2:0] rDestinationRegisterOfRamOutput;

  assign useOutputOfRAM = rUseOutputOfRAM;
  assign destinationRegisterOfRamOutput = rDestinationRegisterOfRamOutput;

  reg                rIoEnabled0;
  reg [addrBits-1:0] rIoAddress0;
  reg                rIoReadWriteMode0;
  reg [dataBits-1:0] rIoWriteValue0;
  reg [2:0]          rIoReadRegister0;

  assign ioEnabled0       = rIoEnabled0;
  assign ioAddress0       = rIoAddress0;
  assign ioReadWriteMode0 = rIoReadWriteMode0;
  assign ioWriteValue0    = rIoWriteValue0;
  assign ioReadRegister0  = rIoReadRegister0;

  reg rNeedsFullFetch;
  assign needsFullFetch = rNeedsFullFetch;

  reg [8:0]          rNextProgramCounter;
  reg [addrBits-1:0] rNextStackPointer;
  reg [addrBits-1:0] rNextCallStackPointer;
  reg [dataBits-1:0] rNextTopOfStack1;
  reg [dataBits-1:0] rNextTopOfStack2;
  reg [dataBits-1:0] rNextTopOfStack3;

  assign nextProgramCounter   = rNextProgramCounter;
  assign nextStackPointer     = rNextStackPointer;
  assign nextCallStackPointer = rNextCallStackPointer;
  assign nextTopOfStack1      = rNextTopOfStack1;
  assign nextTopOfStack2      = rNextTopOfStack2;
  assign nextTopOfStack3      = rNextTopOfStack3;

  reg [1:0] rStatus;
  assign status = rStatus;

  // SECTION: sub-components

  reg  [dataBits-1:0] aluA;
  reg  [dataBits-1:0] aluB;
  reg  [3:0]          aluFunc;
  reg  [3:0]          condition;
  reg                 updateFlags;
  wire [dataBits-1:0] aluOut;
  reg                 conditionHolds;
  Alu #(.dataBits(dataBits)) alu0(
    .clk(clk),
    .reset(reset),
    .aluA(aluA),
    .aluB(aluB),
    .func(aluFunc),
    .condition(condition),
    .aluOut(aluOut),
    .conditionHolds(conditionHolds),
    .updateFlags(updateFlags),
    .exportedAluFlags(exportedAluFlags),
    .loadFlagsFromSavedState(loadFlagsFromSavedState),
    .savedFlags(savedFlags)
  );

  wire isCompare = operand == `OP_ALU_TEST || operand == `OP_ALU_COMPARE;
  wire aluOpPops2 = isCompare;
  wire aluOpPops1 = ~(aluOpPopsNone || aluOpPops2);
  wire aluOpPopsNone = (operand == `OP_ALU_NOT);

  // SECTION: Controller

  wire [3:0] opcode = instruction[7:4];
  wire [3:0] operand = instruction[3:0];

  // TODO: Throughout this section I have quite a few places where I'm adding small constants. I
  // think these all end up getting generated as separate circuits. This may not be hugely
  // efficient.

  reg rPushNextLower;
  assign pushNextLower = rPushNextLower;

  reg rPushNextUpper;
  assign pushNextUpper = rPushNextUpper;

  // Don't attempt "branch prediction" if any kind of function call operation
  wire isFunctionOp = opcode == `OP_FUNCTION;
  assign programCounterIsIncremented = rNextProgramCounter == expectedNextProgramCounter && !isFunctionOp;

  reg wPop1;
  reg wPop2;
  reg wWrite3;

  always @(*)
    begin
      // Default values for the output of this stage
      rNextProgramCounter   = expectedNextProgramCounter;
      rNextStackPointer     = stackPointer;
      rNextCallStackPointer = callStackPointer;
      rNextTopOfStack1      = topOfStack1;
      rNextTopOfStack2      = topOfStack2;
      rNextTopOfStack3      = topOfStack3;
      rDestinationRegisterOfRamOutput = 3'bx;
      // Default values for control codes
      aluFunc          = 4'bx;
      aluA             = 16'bx;
      aluB             = 16'bx;
      condition        = operand;
      updateFlags      = 0;
      rRamRW           = `RAM_READ;
      rAddr            = 8'bx;
      rUseOutputOfRAM  = 0;
      rDataIn          = 16'bx;
      rStatus          = `EXEC_STATUS_OK;
      rPushNextLower   = 0;
      rPushNextUpper   = 0;
      // I/O
      rIoEnabled0       = 0;
      rIoAddress0       = {addrBits{1'bx}};
      rIoReadWriteMode0 = `RAM_READ;
      rIoWriteValue0    = {dataBits{1'bx}};
      rIoReadRegister0  = 3'bx;
      rNeedsFullFetch   = 0;
      // Communication
      message                = `CORE_MESSAGE_NONE;
      messageChannel         = {addrBits{1'bx}};
      messageJumpDestination = 9'bx;
      messageMessage         = {dataBits{1'bx}};
      messageNumWords        = {addrBits{1'bx}};

      // Treat these like function calls
      wPop1   = 0; // If this is set to true then it is expected that the "caller" sets the first stack element
      wPop2   = 0; // No need on this one
      wWrite3 = 0;
      case (opcode)
        `OP_ALU:
          begin
            // Do the operation
            aluFunc = operand;
            aluA = topOfStack2;
            aluB = topOfStack1;
            updateFlags = enabled;
            rNextTopOfStack1 = aluOut;
            if (aluOpPops1)
              begin
                // Pop 2, push 1
                rNextStackPointer = stackPointer + 1;
                wPop1 = 1;
              end
            else if (aluOpPops2) // i.e. is compare
              wPop2 = 1;
          end
        `OP_PUSH:
          begin
            rNextTopOfStack1 = { 12'b0000, operand };
            rNextTopOfStack2 = topOfStack1;
            rNextTopOfStack3 = topOfStack2;
            rNextStackPointer = stackPointer - 1;
            wWrite3           = 1;
          end
        `OP_PUSH_NEXT_LOWER:
          begin
            rNextTopOfStack1 = { 4'b0000, operand, 8'b0000 };
            rNextTopOfStack2 = topOfStack1;
            rNextTopOfStack3 = topOfStack2;
            rNextStackPointer = stackPointer - 1;
            wWrite3 = 1;
            rPushNextLower = 1;
          end
        `OP_PUSH_NEXT_UPPER:
          begin
            rNextTopOfStack1 = { operand, 12'b0000 };
            rNextTopOfStack2 = topOfStack1;
            rNextTopOfStack3 = topOfStack2;
            rNextStackPointer = stackPointer - 1;
            wWrite3 = 1;
            rPushNextUpper = 1;
          end
        `OP_ADD_SMALL:
          begin
            aluFunc = `OP_ALU_ADD;
            aluA = topOfStack1;
            aluB = { 12'b0000, operand };
            rNextTopOfStack1 = aluOut;
            updateFlags = 0;
          end
        `OP_JUMP:
          begin
            rNextProgramCounter = conditionHolds ? topOfStack1[8:0] : expectedNextProgramCounter;
            if (operand != `OP_CONDITION_NEVER) // i.e. is a normal jump, not nop
              begin
                rNextTopOfStack1 = topOfStack2;
                wPop1 = 1;
              end
          end
        `OP_STACK:
          begin
            case (operand)
              `OP_STACK_DROP:
                begin
                  // Pop 1 from stack and read third of stack on the next cycle regardless
                  wPop1 = 1;
                  rNextTopOfStack1 = topOfStack2;
                end
              `OP_STACK_DUP:
                begin
                  rNextStackPointer = stackPointer - 1;
                  rNextTopOfStack1 = topOfStack1;
                  rNextTopOfStack2 = topOfStack1;
                  rNextTopOfStack3 = topOfStack2;
                  wWrite3 = 1;
                end
              `OP_STACK_ROT:
                begin
                  rNextTopOfStack1 = topOfStack2;
                  rNextTopOfStack2 = topOfStack3;
                  rNextTopOfStack3 = topOfStack1;
                end
              `OP_STACK_SWAP:
                begin
                  rNextTopOfStack1 = topOfStack2;
                  rNextTopOfStack2 = topOfStack1;
                end
              `OP_STACK_TUCK:
                begin
                  rNextTopOfStack1 = topOfStack3;
                  rNextTopOfStack2 = topOfStack1;
                  rNextTopOfStack3 = topOfStack2;
                end
              default:
                begin
                  rStatus = `EXEC_STATUS_DECODE_ERROR;
                end
            endcase
          end
        `OP_FUNCTION:
          begin
            case (operand)
              `OP_FUNCTION_CALL:
                begin
                  rNextProgramCounter = topOfStack1[8:0];
                  // The plan for the I/O micro-ops doesn't yet support encoding the write to the
                  // call stack because it needs to read from a now dead register. This doesn't
                  // matter because it can be done on this cycle instead.
                  rDataIn = {7'b0, expectedNextProgramCounter};
                  rRamRW = `RAM_WRITE;
                  rAddr = callStackPointer;
                  rNextCallStackPointer = callStackPointer + 1;
                  // Pop the call address
                  rNextStackPointer = stackPointer + 1;
                  rNextTopOfStack1 = topOfStack2;
                  rNextTopOfStack2 = topOfStack3;
                  // Read to topOfStack3 with SP + 2 (based on new stack pointer)
                  rIoEnabled0      = 1;
                  rIoAddress0      = stackPointer + 3;
                  rIoReadRegister0 = `REG_S3;
                end
              `OP_FUNCTION_RETURN:
                begin
                  if (callStackPointer == 2) // See SaveState.v
                    begin
                      message = `CORE_MESSAGE_HALT;
                    end
                  else
                    begin
                      // Pop from the call stack
                      rNextCallStackPointer = callStackPointer - 1;
                      // Read the top of call stack and set it to the PC on the next cycle.
                      rAddr = callStackPointer - 1;
                      rUseOutputOfRAM = 1;
                      rDestinationRegisterOfRamOutput = `REG_PC;
                    end
                end
              default:
                rStatus = `EXEC_STATUS_DECODE_ERROR;
            endcase
          end
        `OP_PROCESS:
        begin
          // I.e. if operand is 12, 13, 14, 15, all of which are undefined
          if (operand[3] & operand[2])
            message = `CORE_MESSAGE_NONE;
          else
            message = operand;
          case (operand)
            `OP_PROCESS_START:
              begin
                messageNumWords = topOfStack1[7:0];
                messageJumpDestination = topOfStack2[8:0];
                wPop2 = 1;
              end
            `OP_PROCESS_SEND:
              begin
                messageMessage = topOfStack1;
                messageChannel = topOfStack2[7:0];
                rNextTopOfStack1 = topOfStack2;
                wPop1 = 1;
              end
            `OP_PROCESS_RECEIVE:
              begin
                messageChannel   = topOfStack1[7:0];
              end
            `OP_PROCESS_ENABLE_CHANNEL:
              begin
                messageChannel   = topOfStack1[7:0];
                rNextTopOfStack1 = topOfStack2;
                wPop1            = 1;
              end
            `OP_PROCESS_DISABLE_CHANNEL:
              begin
                messageJumpDestination = topOfStack1[8:0];
                messageChannel         = topOfStack2[7:0];
                wPop2                  = 1;
              end
            `OP_PROCESS_DESTROY_CHANNEL:
              begin
                messageChannel   = topOfStack1[7:0];
                rNextTopOfStack1 = topOfStack2;
                wPop1            = 1;
              end
            `OP_PROCESS_ALT_END:
              begin
                rNextProgramCounter = nextPCOnAlt;
                rNextTopOfStack1 = nextTopOfStackOnAlt;
                rNextTopOfStack2 = topOfStack1;
                rNextTopOfStack3 = topOfStack2;
                wWrite3 = 1;
                rNextStackPointer = stackPointer - 1;
              end
            default: begin end
          endcase
        end
`ifdef ALLOW_ARBITRARY_STACK_READS
        `OP_READ_LOCAL:
          begin
            rNextTopOfStack2 = topOfStack2;
            rNextTopOfStack3 = topOfStack3;
            // Kind of annoying that these need special casing
            if (topOfStack1 == 0) rNextTopOfStack1 = topOfStack2;
            else if (topOfStack1 == 1) rNextTopOfStack1 = topOfStack3;
            else
              begin
                rAddr                           = stackPointer + 1 + topOfStack1[7:0];
                rUseOutputOfRAM                 = 1;
                rDestinationRegisterOfRamOutput = `REG_S1;
              end
          end
`endif
`ifdef ALLOW_ARBITRARY_STACK_WRITES
        `OP_WRITE_LOCAL:
          begin
            rNextStackPointer = stackPointer + 2;
            rAddr             = stackPointer + 2 + topOfStack1[7:0];
            rRamRW            = `RAM_WRITE;
            rDataIn            = topOfStack2;
            rNeedsFullFetch   = 1;
          end
`endif
`ifdef ALLOW_ARBITRARY_STACK_READS
        `OP_READ_LOCAL_OFFSET:
        begin
          rNextTopOfStack2 = topOfStack1;
          rNextTopOfStack3 = topOfStack2;
          rNextStackPointer = stackPointer - 1;
          // Write the third of stack on this cycle
          rAddr = stackPointer + 2;
          rRamRW = `RAM_WRITE;
          rDataIn = topOfStack3;
          // Similar special casing to the previous one
          if (operand == 0)      rNextTopOfStack1 = topOfStack1;
          else if (operand == 1) rNextTopOfStack1 = topOfStack2;
          else if (operand == 2) rNextTopOfStack1 = topOfStack3;
          else
            begin
              // Read the value on the next cycle
              rIoEnabled0       = 1;
              rIoAddress0       = stackPointer + { 4'b0, operand };
              rIoReadWriteMode0 = `RAM_READ;
              rIoReadRegister0  = `REG_S1;
            end
        end
`endif
`ifdef ALLOW_ARBITRARY_STACK_WRITES
        `OP_WRITE_LOCAL_OFFSET:
        begin
          rNextTopOfStack1 = operand == 0 ? topOfStack1 : topOfStack2;
          rNextTopOfStack2 = operand == 1 ? topOfStack1 : topOfStack3;
          rNextTopOfStack3 = operand == 2 ? topOfStack1 : topOfStack3;
          rNextStackPointer = stackPointer + 1;
          if (operand != 0 && operand != 1)
            begin
              // Actually do the write on this cycle
              rAddr = stackPointer + 8'd1 + { 4'b0, operand };
              rRamRW = `RAM_WRITE;
              rDataIn = topOfStack1;
            end

          // On the next cycle, read the new third of stack
          rIoEnabled0 = 1;
          rIoAddress0 = stackPointer + 3;
          rIoReadWriteMode0 = `RAM_READ;
          rIoReadRegister0 = `REG_S3;
        end
`endif
        default:
          rStatus = `EXEC_STATUS_DECODE_ERROR;
      endcase


      if (wPop1)
        begin
          rNextTopOfStack2 = topOfStack3;
          rNextStackPointer = stackPointer + 1;
          // Read the top of stack 3 (offset +2 from new stack pointer)
          rAddr = stackPointer + 3;
          // Catch the output of RAM on the next cycle
          rUseOutputOfRAM = 1;
          rDestinationRegisterOfRamOutput = `REG_S3;
        end
      else if (wPop2)
        begin
          rNextTopOfStack1 = topOfStack3;
          rNextStackPointer = stackPointer + 2;
          // Read new top of stack 2 (offset +1 from new stack pointer)
          rAddr = stackPointer + 3;
          // Catch the output of RAM on the next cycle
          rUseOutputOfRAM = 1;
          rDestinationRegisterOfRamOutput = `REG_S2;
          // Read to topOfStack3 with SP + 2 (based on new stack pointer,
          // hence plus 3)
          rIoEnabled0      = 1;
          rIoAddress0      = stackPointer + 4;
          rIoReadRegister0 = `REG_S3;
        end
      else if (wWrite3)
        begin
          rRamRW = `RAM_WRITE;
          rAddr  = stackPointer + 2;
          rDataIn = topOfStack3;
        end
    end

endmodule
