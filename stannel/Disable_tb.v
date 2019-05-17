`include "defaults.vh"

module Disable_tb();
  // Clock
  reg clk;
  always #1 clk = clk !== 1'b1;

  // Memory
  parameter romFile = "zeroes.hex";

  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  reg  [addrBits-1:0] address;
  reg  [dataBits-1:0] dataIn;
  wire [dataBits-1:0] dataOut;
  reg                 readWriteMode;

  IceRam #(.addrBits(addrBits), .dataBits(dataBits), .romFile(romFile)) memory (
    .clk          (clk),
    .address      (address),
    .readWriteMode(readWriteMode),
    .dataIn       (dataIn),
    .dataOut      (dataOut)
  );

  // Test component
  reg                reset = 0;
  reg                enabled = 0;
  reg [addrBits-1:0] channel = 0;
  reg [dataBits-1:0] message;
  reg [addrBits-1:0] rxPid;

  reg                finished;
  reg                shouldScheduleSender;
  reg [addrBits-1:0] scheduleTxPid;
  reg                hasDeliveredMessage;
  reg [dataBits-1:0] deliveredMessage;
  reg                rxHadMessageInAlt = 0;
  reg                rxHasMessageInAlt;

  Disable #(.addrBits(addrBits), .dataBits(dataBits)) dis0 (
    .clk                     (clk),
    .reset                   (reset),
    .enabled                 (enabled),
    .finished                (finished),
    .address                 (address),
    .readWriteMode           (readWriteMode),
    .dataOut                 (dataOut),
    .dataIn                  (dataIn),
    .channel                 (channel),
    .rxPid                   (rxPid),
    .shouldScheduleSender    (shouldScheduleSender),
    .scheduleTxPid           (scheduleTxPid),
    .hasDeliveredMessage     (hasDeliveredMessage),
    .deliveredMessage        (deliveredMessage),
    .rxHadMessageInAlt       (rxHadMessageInAlt),
    .rxHasMessageInAlt       (rxHasMessageInAlt)
  );

  task disableNoSender;
    begin
      enabled <= 1;
      channel <= 2;
      rxPid <= 7;
      memory.ram[2] <= 7;
      @(posedge finished)
        begin
          enabled <= 0;
          if (shouldScheduleSender) $error("Shouldn't schedule sender, both should wait");
          if (hasDeliveredMessage) $error("Shouldn't have delivered message");
          if (memory.ram[2] != 0) $error("Didn't clear memory");
        end
    end
  endtask

  task disableSomeSender;
    begin
      enabled <= 1;
      channel <= 8;
      memory.ram[8] = 8;
      memory.ram[9] = 42;
      rxPid <= 3;
      @(posedge finished)
        begin
          enabled <= 0;
          if (!shouldScheduleSender) $error("Sender should be scheduled");
          if (scheduleTxPid != 8) $error("Scheduled tx pid not sending pid");
          if (!hasDeliveredMessage) $error("Doesn't have message");
          if (deliveredMessage != 42) $error("Delivered message not as expected");
          if (memory.ram[8] != 0) $error("Memory not zeroed");
          if (!rxHasMessageInAlt) $error("Should have message in alt");
        end
    end
  endtask

  task disableWithSomeMessageAlreadyButNotThisChannel;
    begin
      enabled <= 1;
      rxHadMessageInAlt <= 1;
      channel <= 10;
      rxPid = 12;
      memory.ram[10] = { 8'b0, rxPid };
      @(posedge finished)
        begin
          enabled <= 0;
          if (shouldScheduleSender) $error("Shouldn't be scheduling a sender");
          if (hasDeliveredMessage) $error("Shouldn't have a delivered message");
          if (memory.ram[channel] != 0) $error("Should have cleared memory (not %h)", memory.ram[channel]);
        end
    end
  endtask

  task disableWithSomeMessageAlready;
    begin
      enabled <= 1;
      rxHadMessageInAlt <= 1;
      channel <= 10;
      rxPid <= 12;
      memory.ram[10] <= 13;
      @(posedge finished)
        begin
          enabled <= 0;
          if (shouldScheduleSender) $error("Shouldn't be scheduling a sender");
          if (hasDeliveredMessage) $error("Shouldn't have a delivered message");
          if (memory.ram[channel] != 13) $error("Shouldn't have cleared memory");
        end
    end
  endtask


  // No receiving process, so therefore should deschedule sender
   initial begin
    $dumpfile("Disable_tb.vcd");
    $dumpvars(0, Disable_tb);

    #2 reset <= 1;

    #3 disableNoSender;
    #2 disableSomeSender;
    #2 disableWithSomeMessageAlreadyButNotThisChannel;
    #2 disableWithSomeMessageAlready;

    #2 $finish;
  end
endmodule
