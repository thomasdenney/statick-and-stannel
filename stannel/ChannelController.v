`include "defaults.vh"
`include "channels.vh"

// Should not be reset between uses. Set channelOperation to NULL_MESSAGE to
// ensure this module does nothing. Outputs are valid for the single cycle
// after finished is set to 1. Inputs must remain valid until finished is 1.
module ChannelController #(
  parameter addrBits  = `ADDRESS_BITS, // Address bits must be less than or equal to data bits
  parameter dataBits  = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    input  wire                enabled,
    output reg                 finished,
    // Section: channel operation inputs
    input  wire [3:0]          channelOperationIn,
    input  wire [addrBits-1:0] channelIn,
    input  wire [dataBits-1:0] messageIn,
    input  wire [addrBits-1:0] pidIn,
    input  wire                rxHadMessageInAlt,
    // Section channel message outputs
    output reg                 hasChannelOut,
    output reg  [addrBits-1:0] channelOut,
    output reg                 hasMessageOut,
    output reg  [dataBits-1:0] messageOut,
    output reg                 hasSchedulePidOut,
    output reg  [addrBits-1:0] schedulePidOut,
    output reg                 hasDeschedulePidOut,
    output reg  [addrBits-1:0] deschedulePidOut,
    output reg                 rxHasMessageInAlt
  );

  // Memory
  localparam USER_THIS = 0;
  localparam USER_HEAP = 1;
  localparam USER_SEND = 2;
  localparam USER_RECV = 3;
  localparam USER_ENAB = 4;
  localparam USER_DISA = 5;
  reg [2:0] wMemoryUser;

  MemoryControllerExternal6 #(.addrBits(addrBits), .dataBits(dataBits)) memoryMultiplexer(
    .address0      (wAddress),
    .readWriteMode0(wReadWriteMode),
    .dataIn0       (wDataIn),

    .address1      (heapAddress),
    .readWriteMode1(heapReadWriteMode),
    .dataIn1       (heapDataIn),

    .address2      (sendAddress),
    .readWriteMode2(sendReadWriteMode),
    .dataIn2       (sendDataIn),

    .address3      (receiveAddress),
    .readWriteMode3(receiveReadWriteMode),
    .dataIn3       (receiveDataIn),

    .address4      (enableAddress),
    .readWriteMode4(enableReadWriteMode),
    .dataIn4       (enableDataIn),

    .address5      (disableAddress),
    .readWriteMode5(disableReadWriteMode),
    .dataIn5       (disableDataIn),

    .cellToUser    (wMemoryUser),
    .address       (address),
    .readWriteMode (rwMode),
    .dataIn        (dataIn)
  );

  reg [addrBits-1:0] heapAddress;
  reg [dataBits-1:0] heapDataIn;
  reg                heapReadWriteMode;

  reg [addrBits-1:0] sendAddress;
  reg [dataBits-1:0] sendDataIn;
  reg                sendReadWriteMode;

  reg [addrBits-1:0] receiveAddress;
  reg [dataBits-1:0] receiveDataIn;
  reg                receiveReadWriteMode;

  reg [addrBits-1:0] enableAddress;
  reg [dataBits-1:0] enableDataIn;
  reg                enableReadWriteMode;

  reg [addrBits-1:0] disableAddress;
  reg [dataBits-1:0] disableDataIn;
  reg                disableReadWriteMode;

  reg [addrBits-1:0] wAddress;
  reg [dataBits-1:0] wDataIn;
  reg                wReadWriteMode;

  reg  [addrBits-1:0] address;
  reg  [dataBits-1:0] dataIn;
  reg                 rwMode;
  wire [dataBits-1:0] dataOut;

  // Memory subcomponents
  IceRam #(.addrBits(addrBits), .dataBits(dataBits)) ram0(
    .clk          (clk),
    .address      (address),
    .readWriteMode(rwMode),
    .dataIn       (dataIn),
    .dataOut      (dataOut)
  );

  reg heapFinished;

  reg                 wAlloc;
  reg  [addrBits-1:0] allocAddress;
  reg                 wFree;
  reg  [addrBits-1:0] wFreeAddress;

  Heap #(.addrBits(addrBits), .dataBits(dataBits), .allocSize(2)) heap0(
    .clk          (clk),
    .reset        (reset),
    .finished     (heapFinished),
    .address      (heapAddress),
    .readWriteMode(heapReadWriteMode),
    .dataOut      (dataOut),
    .dataIn       (heapDataIn),
    .alloc        (wAlloc),
    .allocAddress (allocAddress),
    .free         (wFree),
    .freeAddress  (wFreeAddress)
  );

  // Internal state machines

  reg                sendFinished;
  reg                sendShouldScheduleReceiver;
  reg                sendShouldDescheduleSender;
  reg [addrBits-1:0] sendScheduleRxPid;
  reg [dataBits-1:0] sendDeliveredMessage;
  reg                sendAddToAlternationReadySet;

  Send #(.addrBits(addrBits), .dataBits(dataBits)) send0 (
    .clk                   (clk),
    .reset                 (wSendEnabled),
    .finished              (sendFinished),
    .address               (sendAddress),
    .readWriteMode         (sendReadWriteMode),
    .dataOut               (dataOut),
    .dataIn                (sendDataIn),
    .channel               (channelIn),
    .message               (messageIn),
    .txPid                 (pidIn),
    .alternationSet        (alternationSet),
    .alternationReadySet   (alternationReadySet),
    .shouldScheduleReceiver(sendShouldScheduleReceiver),
    .shouldDescheduleSender(sendShouldDescheduleSender),
    .scheduleRxPid         (sendScheduleRxPid),
    .deliveredMessage      (sendDeliveredMessage),
    .addToAlternationReadySet(sendAddToAlternationReadySet)
  );

  reg                wReceiveEnabled;
  reg                receiveFinished;
  reg                receiveShouldDescheduleReceiver;
  reg                receiveShouldScheduleSender;
  reg [addrBits-1:0] receiveSender;
  reg                receiveHasDeliveredMessage;
  reg [dataBits-1:0] receiveDeliveredMessage;

  Receive #(.addrBits(addrBits), .dataBits(dataBits)) rcv0(
    .clk                     (clk),
    .reset                   (wReceiveEnabled),
    .finished                (receiveFinished),
    .address                 (receiveAddress),
    .readWriteMode           (receiveReadWriteMode),
    .dataOut                 (dataOut),
    .dataIn                  (receiveDataIn),
    .channel                 (channelIn),
    .rxPid                   (pidIn),
    .shouldScheduleSender    (receiveShouldScheduleSender),
    .shouldDescheduleReceiver(receiveShouldDescheduleReceiver),
    .scheduleTxPid           (receiveSender),
    .hasDeliveredMessage     (receiveHasDeliveredMessage),
    .deliveredMessage        (receiveDeliveredMessage)
  );

  reg wEnableEnabled;
  reg enableFinished;
  reg enableRxCanReceive;

  Enable #(.addrBits(addrBits), .dataBits(dataBits)) e0 (
    .clk          (clk),
    .reset        (wEnableEnabled),
    .finished     (enableFinished),
    .address      (enableAddress),
    .readWriteMode(enableReadWriteMode),
    .dataOut      (dataOut),
    .dataIn       (enableDataIn),
    .channel      (channelIn),
    .rxPid        (pidIn),
    .rxCanReceive (enableRxCanReceive)
  );

  reg                wDisableEnabled;
  reg                disableFinished;
  reg                disableShouldScheduleSender;
  reg [addrBits-1:0] disableSender;
  reg                disableHasDeliveredMessage;
  reg [dataBits-1:0] disableDeliveredMessage;

  Disable #(.addrBits(addrBits), .dataBits(dataBits)) dis0(
    .clk                     (clk),
    .reset                   (reset),
    .enabled                 (wDisableEnabled),
    .finished                (disableFinished),
    .address                 (disableAddress),
    .readWriteMode           (disableReadWriteMode),
    .dataOut                 (dataOut),
    .dataIn                  (disableDataIn),
    .channel                 (channelIn),
    .rxPid                   (pidIn),
    .shouldScheduleSender    (disableShouldScheduleSender),
    .scheduleTxPid           (disableSender),
    .hasDeliveredMessage     (disableHasDeliveredMessage),
    .deliveredMessage        (disableDeliveredMessage),
    .rxHadMessageInAlt       (rxHadMessageInAlt),
    .rxHasMessageInAlt       (rxHasMessageInAlt)
  );

  // State
  localparam STATE_INIT            = 0;
  localparam STATE_CREATE_CHANNEL  = 1;
  localparam STATE_DESTROY_CHANNEL = 2;
  localparam STATE_SEND_MESSAGE    = 3;
  localparam STATE_ZERO_0          = 4;
  localparam STATE_ZERO_1          = 5;
  localparam STATE_RECEIVE_MESSAGE = 6;
  localparam STATE_ENABLE_CHANNEL  = 7;
  localparam STATE_DISABLE_CHANNEL = 8;
  reg [3:0] rState;

  reg [`CELL_COUNT:0] alternationSet;
  reg [`CELL_COUNT:0] alternationReadySet;

  // Signals
  reg [3:0]          wNextState;
  reg                wHasChannelOut;
  reg [addrBits-1:0] wChannelOut;
  reg                wFinished;
  reg                wSendEnabled;
  reg                wHasSchedulePidOut;
  reg [addrBits-1:0] wSchedulePidOut;
  reg                wHasDeschedulePidOut;
  reg [addrBits-1:0] wDeschedulePidOut;
  reg                wHasMessageOut;
  reg [dataBits-1:0] wMessageOut;

  reg [`CELL_COUNT:0] wNewAlternationSet;
  reg [`CELL_COUNT:0] wNewAlternationReadySet;

  wire [`CELL_COUNT:0] alternationFlag = `CELL_COUNT_CONST_1 << pidIn;
  wire inAlternationReadySet = (alternationReadySet & alternationFlag) != 0;

  // Signal processing
  always @(posedge clk)
  begin
    if (!reset)
      begin
        rState              <= STATE_INIT;
        finished            <= 0;
        alternationSet      <= 0;
        alternationReadySet <= 0;
      end
    else if (enabled)
      begin
        finished             <= wFinished;
        hasChannelOut        <= wHasChannelOut;
        hasSchedulePidOut    <= wHasSchedulePidOut;
        hasDeschedulePidOut  <= wHasDeschedulePidOut;
        hasMessageOut        <= wHasMessageOut;
        channelOut           <= wChannelOut;
        schedulePidOut       <= wSchedulePidOut;
        deschedulePidOut     <= wDeschedulePidOut;
        messageOut           <= wMessageOut;
        alternationSet       <= wNewAlternationSet;
        alternationReadySet  <= wNewAlternationReadySet;

        rState <= wNextState;
      end
    else
      begin
        rState   <= STATE_INIT;
        finished <= 0;
      end
  end

  // Combinatorial logic
  always @(*)
  begin
    wAddress                = {addrBits{1'bx}};
    wDataIn                 = {dataBits{1'bx}};
    wReadWriteMode          = `RAM_READ;
    wMemoryUser             = USER_THIS;
    wNextState              = rState;
    wAlloc                  = 0;
    wFree                   = 0;
    wFreeAddress            = 0;
    wHasChannelOut          = 0;
    wChannelOut             = channelOut; // Needed for a few cycles
    wFinished               = 0;
    wHasSchedulePidOut      = 0;
    wSchedulePidOut         = {addrBits{1'bx}};
    wHasDeschedulePidOut    = 0;
    wDeschedulePidOut       = {addrBits{1'bx}};
    wHasMessageOut          = 0;
    wMessageOut             = {dataBits{1'bx}};
    wSendEnabled            = 0;
    wReceiveEnabled         = 0;
    wEnableEnabled          = 0;
    wDisableEnabled         = 0;
    wNewAlternationSet      = alternationSet;
    wNewAlternationReadySet = alternationReadySet;
    case (rState)
      STATE_INIT:
        begin
          if (enabled)
            begin
              case (channelOperationIn)
                `CREATE_CHANNEL:
                  begin
                    wMemoryUser = USER_HEAP;
                    wAlloc      = enabled;
                    wNextState  = STATE_CREATE_CHANNEL;
                  end
                `DESTROY_CHANNEL:
                  begin
                    wMemoryUser  = USER_HEAP;
                    wFree        = enabled;
                    wFreeAddress = channelIn;
                    wNextState   = STATE_DESTROY_CHANNEL;
                  end
                `SEND_MESSAGE:
                  begin
                    wMemoryUser  = USER_SEND;
                    wNextState   = STATE_SEND_MESSAGE;
                    wSendEnabled = enabled;
                  end
                `RECEIVE_MESSAGE:
                  begin
                    wMemoryUser     = USER_RECV;
                    wNextState      = STATE_RECEIVE_MESSAGE;
                    wReceiveEnabled = enabled;
                  end
                `ENABLE_CHANNEL:
                  begin
                    wMemoryUser     = USER_ENAB;
                    wNextState      = STATE_ENABLE_CHANNEL;
                    wReceiveEnabled = enabled;
                  end
                `DISABLE_CHANNEL:
                  begin
                    wMemoryUser     = USER_DISA;
                    wNextState      = STATE_DISABLE_CHANNEL;
                    wDisableEnabled = enabled;
                  end
                `ALT_START:
                  begin
                    wNewAlternationSet = alternationSet | alternationFlag;
                    wFinished          = 1;
                  end
                `ALT_WAIT:
                  begin
                    wFinished = 1;
                    if (~inAlternationReadySet)
                      begin
                        wHasDeschedulePidOut = 1;
                        wDeschedulePidOut    = pidIn;
                      end
                  end
                `ALT_END:
                  begin
                    wFinished = 1;
                    wNewAlternationSet = alternationSet & ~alternationFlag;
                    wNewAlternationReadySet = alternationReadySet & ~alternationFlag;
                    wFinished = 1;
                  end
                default: begin end
              endcase
            end
        end
      STATE_CREATE_CHANNEL:
        begin
          wNextState     = heapFinished ? STATE_ZERO_0 : rState;
          wChannelOut    = allocAddress;
        end
      STATE_DESTROY_CHANNEL:
        begin
          wMemoryUser  = USER_HEAP;
          wFree        = 1;
          wFreeAddress = channelIn;
          wFinished    = heapFinished;
          wNextState   = heapFinished ? STATE_INIT : rState;
        end
      STATE_SEND_MESSAGE:
        begin
          wMemoryUser           = USER_SEND;
          wSendEnabled          = 1;
          wFinished             = sendFinished;
          wNextState            = sendFinished ? STATE_INIT : rState;
          wHasSchedulePidOut    = sendShouldScheduleReceiver;
          wSchedulePidOut       = sendScheduleRxPid;
          wHasDeschedulePidOut  = sendShouldDescheduleSender;
          wDeschedulePidOut     = pidIn;
          wHasMessageOut        = sendShouldScheduleReceiver;
          wMessageOut           = sendDeliveredMessage;
          if (sendFinished && sendAddToAlternationReadySet)
            wNewAlternationReadySet = alternationReadySet | (`CELL_COUNT_CONST_1 << sendScheduleRxPid);
        end
      STATE_RECEIVE_MESSAGE:
        begin
          wMemoryUser           = USER_RECV;
          wReceiveEnabled       = 1;
          wFinished             = receiveFinished;
          wNextState            = receiveFinished ? STATE_INIT : rState;
          wHasSchedulePidOut    = receiveShouldScheduleSender;
          wSchedulePidOut       = receiveSender;
          wHasDeschedulePidOut  = receiveShouldDescheduleReceiver;
          wDeschedulePidOut     = pidIn;
          wHasMessageOut        = receiveHasDeliveredMessage;
          wMessageOut           = receiveDeliveredMessage;
        end
      STATE_ENABLE_CHANNEL:
        begin
          wEnableEnabled        = ~enableFinished;
          wNextState            = enableFinished ? STATE_INIT : rState;
          wMemoryUser           = wEnableEnabled ? USER_ENAB : USER_THIS;
          wFinished             = enableFinished;
          if (enableRxCanReceive)
            wNewAlternationReadySet = alternationReadySet | alternationFlag;
        end
      STATE_DISABLE_CHANNEL:
        begin
          wDisableEnabled    = ~disableFinished;
          wMemoryUser        = wDisableEnabled ? USER_DISA : USER_THIS;
          wNextState         = disableFinished ? STATE_INIT : rState;
          wFinished          = disableFinished;
          wHasSchedulePidOut = disableShouldScheduleSender;
          wSchedulePidOut    = disableSender;
          wHasMessageOut     = disableHasDeliveredMessage;
          wMessageOut        = disableDeliveredMessage;
        end
      STATE_ZERO_0:
        begin
          wAddress       = channelOut;
          wReadWriteMode = `RAM_WRITE;
          wDataIn        = {dataBits{1'b0}};
          wNextState     = STATE_ZERO_1;
        end
      STATE_ZERO_1:
        begin
          wAddress       = channelOut;
          wReadWriteMode = `RAM_WRITE;
          wDataIn        = {dataBits{1'b0}};
          wNextState     = STATE_INIT;
          wHasChannelOut = 1;
          wFinished      = 1;
        end
      default: begin end
    endcase
  end

endmodule
