`include "defaults.vh"

module Send_tb();
  // Clock
  reg clk;
  always #1 clk = clk !== 1'b1;

  // Memory
  parameter romFile = "zeroes.hex";

  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  wire [addrBits-1:0] address;
  wire [dataBits-1:0] dataIn;
  wire [dataBits-1:0] dataOut;
  wire                readWriteMode;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(romFile)) memory (
    .clk          (clk),
    .address      (address),
    .readWriteMode(readWriteMode),
    .dataIn       (dataIn),
    .dataOut      (dataOut)
  );

  // Test component
  reg                reset = 0;
  reg [addrBits-1:0] channel = 0;
  reg [dataBits-1:0] message;
  reg [addrBits-1:0] txPid;
  reg [`CELL_COUNT:0] alternationSet = 17'b1011;
  reg [`CELL_COUNT:0]           alternationReadySet = 0;

  reg                finished;
  reg                shouldScheduleReceiver;
  reg                shouldDescheduleSender;
  reg [addrBits-1:0] scheduleRxPid;
  reg [dataBits-1:0] deliveredMessage;
  reg                addToAlternationReadySet;

  Send #(.addrBits(addrBits), .dataBits(dataBits)) send0 (
    .clk                     (clk),
    .reset                   (reset),
    .finished                (finished),
    .address                 (address),
    .readWriteMode           (readWriteMode),
    .dataOut                 (dataOut),
    .dataIn                  (dataIn),
    .channel                 (channel),
    .message                 (message),
    .txPid                   (txPid),
    .alternationSet          (alternationSet),
    .alternationReadySet     (alternationReadySet),
    .shouldScheduleReceiver  (shouldScheduleReceiver),
    .shouldDescheduleSender  (shouldDescheduleSender),
    .scheduleRxPid           (scheduleRxPid),
    .deliveredMessage        (deliveredMessage),
    .addToAlternationReadySet(addToAlternationReadySet)
  );

  // No receiving process, so therefore should deschedule sender
  task noReceiverTest;
    begin
      reset   <= 1;
      channel <= 2;
      message <= 42;
      txPid   <= 12;

      @(posedge finished)
        begin
          reset <= 0;
          if (!shouldDescheduleSender) $error("Should deschedule sender");
          if (shouldScheduleReceiver) $error("Shouldn't schedule receiver");
          if (deliveredMessage != message) $error("Didn't deliver message");
          if (memory.ram[channel] != {8'b0, txPid}) $error("Didn't set sending process");
          if (memory.ram[channel+1] != message) $error("Didn't set sent message");
          if (addToAlternationReadySet) $error("Shouldn't add to alternation ready set");
        end
    end
  endtask

  // Receiving process, should schedule it
  task someReceiverTest;
    begin
      channel       <= 4;
      memory.ram[4] <= 7;
      reset         <= 1;

      @(posedge finished)
        begin
          reset <= 0;
          if (shouldDescheduleSender) $error("Shouldn't deschedule sender");
          if (!shouldScheduleReceiver) $error("Should schedule receiver");
          if (scheduleRxPid != 7) $error("Should have scheduled process 7");
          if (deliveredMessage != message) $error("Didn't deliver message");
          if (addToAlternationReadySet) $error("Shouldn't add to alternation ready set");
        end
    end
  endtask

  // Receiving process exists and is in alternation
  task altReceiverTest;
    begin
      channel        <= 8;
      memory.ram[8]  <= 9;
      alternationSet <= (17'b1 << 9) | alternationSet;
      reset          <= 1;

      @(posedge finished)
        begin
          reset <= 0;
          if (!shouldDescheduleSender) $error("Should deschedule receiver");
          if (!shouldScheduleReceiver) $error("Should schedule receiver");
          if (scheduleRxPid != 9) $error("Should have scheduled process 9");
          if (!addToAlternationReadySet) $error("Should have added to alternation ready set");
          if (deliveredMessage != message) $error("Didn't deliver message");
        end
    end
  endtask

  // Receiving process exists and is in alternation that has already received
  // something.
  task altReceiverTest2;
    begin
      channel        <= 8;
      memory.ram[8]  <= 9;
      alternationSet <= (`CELL_COUNT_CONST_1 << 9) | alternationSet;
      alternationReadySet <= `CELL_COUNT_CONST_1 << 9;
      reset          <= 1;

      @(posedge finished)
        begin
          reset <= 0;
          if (!shouldDescheduleSender) $error("Should deschedule sender");
          if (shouldScheduleReceiver) $error("Shouldn't schedule receiver");
          if (addToAlternationReadySet) $error("Shouldn't have added to alternation ready set");
        end
    end
  endtask

  initial begin
    $dumpfile("Send_tb.vcd");
    $dumpvars(0, Send_tb);

    #3 noReceiverTest;
    #2 someReceiverTest;
    #2 altReceiverTest;
    #2 altReceiverTest2;
    #2 $finish;
  end
endmodule
