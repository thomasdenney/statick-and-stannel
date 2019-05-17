`include "defaults.vh"

module Receive_tb();
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
  reg [addrBits-1:0] channel = 0;
  reg [dataBits-1:0] message;
  reg [addrBits-1:0] rxPid;

  reg                finished;
  reg                shouldScheduleSender;
  reg                shouldDescheduleReceiver;
  reg [addrBits-1:0] scheduleTxPid;
  reg                hasDeliveredMessage;
  reg [dataBits-1:0] deliveredMessage;

  Receive #(.addrBits(addrBits), .dataBits(dataBits)) rcv0 (
    .clk                     (clk),
    .reset                   (reset),
    .finished                (finished),
    .address                 (address),
    .readWriteMode           (readWriteMode),
    .dataOut                 (dataOut),
    .dataIn                  (dataIn),
    .channel                 (channel),
    .rxPid                   (rxPid),
    .shouldScheduleSender    (shouldScheduleSender),
    .shouldDescheduleReceiver(shouldDescheduleReceiver),
    .scheduleTxPid           (scheduleTxPid),
    .hasDeliveredMessage     (hasDeliveredMessage),
    .deliveredMessage        (deliveredMessage)
  );

  task receiveNoSender;
    begin
      reset <= 1;
      channel <= 2;
      rxPid <= 7;
      @(posedge finished)
        begin
          reset <= 0;
          if (!shouldDescheduleReceiver) $error("Expected to deschedule receiver");
          if (shouldScheduleSender) $error("Shouldn't schedule sender, both should wait");
          if (hasDeliveredMessage) $error("Shouldn't have delivered message");
          if (memory.ram[2] != rxPid) $error("Didn't write rx pid to memory");
        end
    end
  endtask

  task receiveSomeSender;
    begin
      reset <= 1;
      channel <= 8;
      memory.ram[8] = 8;
      memory.ram[9] = 42;
      rxPid <= 3;
      @(posedge finished)
        begin
          reset <= 0;
          if (shouldDescheduleReceiver) $error("Receiver should continue");
          if (!shouldScheduleSender) $error("Sender should be scheduled");
          if (scheduleTxPid != 8) $error("Scheduled tx pid not sending pid");
          if (!hasDeliveredMessage) $error("Doesn't have message");
          if (deliveredMessage != 42) $error("Delivered message not as expected");
          if (memory.ram[8] != 0) $error("Memory not zeroed");
        end
    end
  endtask

  // No receiving process, so therefore should deschedule sender
   initial begin
    $dumpfile("Receive_tb.vcd");
    $dumpvars(0, Receive_tb);

    #3 receiveNoSender;
    #2 receiveSomeSender;

    #2 $finish;
  end
endmodule
