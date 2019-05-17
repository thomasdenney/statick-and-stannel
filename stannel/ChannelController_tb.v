`include "defaults.vh"
`include "channels.vh"
`include "messages.vh"

module ChannelController_tb();
  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  // Clock
  reg clk;
  always #1 clk = clk !== 1'b1;

  // Test component
  reg                reset = 0;
  reg                enabled;
  reg [3:0]          channelOperationIn;
  reg [addrBits-1:0] channelIn = 0;
  reg [dataBits-1:0] messageIn = 0;
  reg [addrBits-1:0] pidIn     = 0;

  reg                finished;
  reg                hasChannelOut;
  reg [addrBits-1:0] channelOut;
  reg                hasMessageOut;
  reg [dataBits-1:0] messageOut;
  reg                hasSchedulePidOut;
  reg [addrBits-1:0] schedulePidOut;
  reg                hasDeschedulePidOut;
  reg [addrBits-1:0] deschedulePidOut;
  reg                rxHadMessageInAlt = 0;
  reg                rxHasMessageInAlt;

  ChannelController #(.addrBits(addrBits), .dataBits(dataBits)) cc0 (
    .clk                (clk),
    .reset              (reset),
    .enabled            (enabled),
    .finished           (finished),
    .channelOperationIn (channelOperationIn),
    .channelIn          (channelIn),
    .messageIn          (messageIn),
    .pidIn              (pidIn),
    .hasChannelOut      (hasChannelOut),
    .channelOut         (channelOut),
    .hasMessageOut      (hasMessageOut),
    .messageOut         (messageOut),
    .hasSchedulePidOut  (hasSchedulePidOut),
    .schedulePidOut     (schedulePidOut),
    .hasDeschedulePidOut(hasDeschedulePidOut),
    .deschedulePidOut   (deschedulePidOut),
    .rxHadMessageInAlt  (rxHadMessageInAlt),
    .rxHasMessageInAlt  (rxHasMessageInAlt)
  );

  task createChannelTest;
    begin
      channelOperationIn <= `CREATE_CHANNEL;
      enabled            <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (!hasChannelOut) $error("Didn't create channel");
          if (channelOut != 0) $error("Created channel is not channel 0");
          if (hasMessageOut) $error("Shouldn't have message out");
          if (hasSchedulePidOut) $error("Should't have scheduled process");
          if (hasDeschedulePidOut) $error("shouldn't have descheduled process");
          if (cc0.heap0.heapEnd != 2) $error("Heap end is not as expected");
        end
    end
  endtask

  task sendMessageTest;
    begin
      channelIn          <= 0;
      pidIn              <= 2;
      messageIn          <= 42;
      channelOperationIn <= `SEND_MESSAGE;
      enabled            <= 1;
      @(posedge finished)
        begin
          enabled            <= 0;
          if (!hasDeschedulePidOut) $error("Expected to deschedule a process");
          if (deschedulePidOut != pidIn) $error("Expected to deschedule sender");
          if (hasChannelOut) $error("Shouldn't have channel out");
          if (hasMessageOut) $error("Shouldn't have message out");
          if (hasSchedulePidOut) $error("Shouldn't schedule anything");
          if (cc0.ram0.ram[0] != {8'b0, pidIn}) $error("Didn't write sending pid");
          if (cc0.ram0.ram[1] != messageIn) $error("Didn't write sent message");
        end
    end
  endtask

  task recvMessageTest;
    begin
      channelIn <= 0;
      pidIn <= 3;
      channelOperationIn <= `RECEIVE_MESSAGE;
      enabled            <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (!hasSchedulePidOut) $error("Expected to schedule sender");
          if (schedulePidOut != 2) $error("Expected to schedule 1");
          if (!hasMessageOut) $error("Expected to have message out");
          if (messageOut != 42) $error("Expected message out to be 42");
          if (hasDeschedulePidOut) $error("Shouldn't deschedule anything");
          if (cc0.ram0.ram[0] != 0) $error("Should have zeroed out memory after successful receive");
        end
    end
  endtask

  task freeChannelTest;
    begin
      channelIn <= 0;
      channelOperationIn <= `DESTROY_CHANNEL;
      enabled            <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (hasChannelOut) $error("Shouldn't have channel out");
          if (hasMessageOut) $error("Shouldn't have message out");
          if (hasSchedulePidOut) $error("Shouldn't schedule anything");
          if (hasDeschedulePidOut) $error("Shouldn't deschedule anything");
          if (cc0.heap0.heapFree != 0) $error("Heap free pointer should be most recently freed channel");
        end
    end
  endtask

  task recvFirstTest;
    begin
      channelIn          <= 0;
      channelOperationIn <= `RECEIVE_MESSAGE;
      pidIn              <= 1;
      enabled            <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (hasChannelOut) $error("Shouldn't have channel out");
          if (hasMessageOut) $error("Shouldn't have message out");
          if (hasSchedulePidOut) $error("Shouldn't have schedule out");
          if (!hasDeschedulePidOut) $error("Should deschedule receiver");
          if (deschedulePidOut != 1) $error("Should deschedule receiver 1");
          if (cc0.ram0.ram[0] != 1) $error("Should have written receiver to memory");
        end
    end
  endtask

  task sendSecondTest;
    begin
      channelIn <= 0;
      channelOperationIn <= `SEND_MESSAGE;
      pidIn <= 2;
      messageIn <= 42;
      enabled <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (hasChannelOut) $error("Shouldn't have channel out");
          if (!hasMessageOut) $error("Should have message out");
          if (messageOut != messageIn) $error("Message in doesn't match message out");
          if (!hasSchedulePidOut) $error("Should schedule receiver");
          if (schedulePidOut != 1) $error("Should schedule receiver 1");
          if (hasDeschedulePidOut) $error("Shouldn't deschedule anything");
          if (cc0.ram0.ram[0] != 0) $error("Should have zeroed memory");
        end
    end
  endtask

  task altStartTest;
    begin
      channelOperationIn <= `ALT_START;
      pidIn <= 1;
      enabled <= 1;
      // Finished stays true from the previous test; then is set to true on the
      // first cycle of this test. It doesn't matter in actual hardware.
      #2 enabled <= 0;
      #2 if (!finished) $error("Should have finished");
      if (cc0.alternationSet != 2) $error("Didn't properly insert into alternation set");
      if (hasChannelOut) $error("Shouldn't have channel out");
      if (hasSchedulePidOut) $error("Shouldn't schedule");
      if (hasDeschedulePidOut) $error("Shouldn't deschedule");
      if (hasMessageOut) $error("Shouldn't have message");
    end
  endtask

  task altWaitTest;
    begin
      channelOperationIn <= `ALT_WAIT;
      enabled <= 1;
      #2 enabled <= 0;
      #2 if (!finished) $error("Should have finished");
      if (hasChannelOut) $error("Shouldn't have channel out");
      if (hasSchedulePidOut) $error("Shouldn't schedule");
      if (!hasDeschedulePidOut) $error("Should deschedule");
      if (deschedulePidOut != pidIn) $error("Should deschedule this process");
      if (hasMessageOut) $error("Shouldn't have message");
    end
  endtask

  task altWaitNoDescheduleTest;
    begin
      channelOperationIn <= `ALT_WAIT;
      enabled <= 1;
      #2 enabled <= 0;
      #2 if (!finished) $error("Should have finished");
      if (hasChannelOut) $error("Shouldn't have channel out");
      if (hasSchedulePidOut) $error("Shouldn't schedule");
      if (hasDeschedulePidOut) $error("Should deschedule");
      if (deschedulePidOut != pidIn) $error("Should deschedule this process");
      if (hasMessageOut) $error("Shouldn't have message");
    end
  endtask

  task altEndTest;
    begin
      channelOperationIn <= `ALT_END;
      pidIn <= 1;
      enabled <= 1;
      #2 enabled <= 0;
      #2 if (!finished) $error("Should have finished");
      if (cc0.alternationSet != 0) $error("Should have removed from alternation set");
      if (hasChannelOut) $error("Shouldn't have channel out");
      if (hasSchedulePidOut) $error("Shouldn't schedule");
      if (hasDeschedulePidOut) $error("Shouldn't deschedule");
      if (hasMessageOut) $error("Shouldn't have message");
    end
  endtask

  task enableChannelTest;
    begin
      channelIn <= 0;
      channelOperationIn <= `ENABLE_CHANNEL;
      pidIn <= 1;
      enabled <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (hasChannelOut) $error("Shouldn't have channel out");
          if (hasSchedulePidOut) $error("Shouldn't schedule");
          if (hasDeschedulePidOut) $error("Shouldn't deschedule");
          if (hasMessageOut) $error("Shouldn't have message");
        end
    end
  endtask

  task disableChannelTest;
    begin
      channelIn <= 0;
      channelOperationIn <= `DISABLE_CHANNEL;
      enabled <= 1;
      pidIn <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (hasChannelOut) $error("Shouldn't have channel out");
          if (!hasSchedulePidOut) $error("Should reschedule sender");
          if (schedulePidOut != 2) $error("Should reschedule sender 2");
          if (!hasMessageOut) $error("Should have message out");
          if (messageOut != messageIn) $error("Message should match sent message");
          if (cc0.ram0.ram[0] != 0) $error("Should have zeroed memory");
        end
    end
  endtask

  task sendChannelMessage;
    input [3:0]          mOp;
    input [addrBits-1:0] mPid;
    input [addrBits-1:0] mChan;
    input [dataBits-1:0] mMessage;
    begin
      channelOperationIn <= mOp;
      pidIn              <= mPid;
      channelIn          <= mChan;
      messageIn          <= mMessage;
      enabled            <= 1;
      @(posedge finished)
        begin
          enabled = 0;
          rxHadMessageInAlt = rxHasMessageInAlt;
        end
    end
  endtask

  task alternationWithSendingAfterWaitTest;
    begin
      reset <= 0;
      rxHadMessageInAlt <= 0;
      cc0.ram0.ram[0] <= 0;
      cc0.ram0.ram[2] <= 0;
      #2 reset <= 1;
      #2 sendChannelMessage(`CORE_MESSAGE_CREATE_CHANNEL, 2, 8'bx, 16'bx);
      #2 sendChannelMessage(`CORE_MESSAGE_CREATE_CHANNEL, 2, 8'bx, 16'bx);
      #2 sendChannelMessage(`CORE_MESSAGE_ALT_START, 2, 8'bx, 16'bx);
      #2 sendChannelMessage(`CORE_MESSAGE_ENABLE_CHANNEL, 2, 0, 16'bx);
      #2 sendChannelMessage(`CORE_MESSAGE_ENABLE_CHANNEL, 2, 2, 16'bx);
      #2 sendChannelMessage(`CORE_MESSAGE_ALT_WAIT, 2, 8'bx, 16'bx);
      if (!hasDeschedulePidOut || deschedulePidOut != 2) $error("Should deschedule p2 on alt wait");
      #2 sendChannelMessage(`CORE_MESSAGE_SEND, 4, 0, 10);
      if (!hasSchedulePidOut || schedulePidOut != 2) $error("Expected to schedule p2 after p4 sends to c0");
      if (!hasDeschedulePidOut || deschedulePidOut != 4) $error("Expected to deschedule p4");
      #2 sendChannelMessage(`CORE_MESSAGE_SEND, 6, 2, 20);
      if (hasSchedulePidOut) $error("Should not schedule p%0d", schedulePidOut);
      if (!hasDeschedulePidOut || deschedulePidOut != 6) $error("Expected deschedule p6");
      #2 sendChannelMessage(`CORE_MESSAGE_DISABLE_CHANNEL, 2, 0, 16'bx);
      if (!rxHasMessageInAlt) $error("Should have message in alternation by now");
      #2 sendChannelMessage(`CORE_MESSAGE_DISABLE_CHANNEL, 2, 2, 16'bx);
      if (!rxHasMessageInAlt) $error("Should have message in alternation by now");
      #2 sendChannelMessage(`CORE_MESSAGE_ALT_END, 2, 8'bx, 16'bx);
    end
  endtask

  task alternationWithSendingBeforeWaitTest;
    begin
      reset <= 0;
      rxHadMessageInAlt <= 0;
      cc0.ram0.ram[0] <= 0;
      cc0.ram0.ram[2] <= 0;
      #2 reset <= 1;
      #2 sendChannelMessage(`CORE_MESSAGE_CREATE_CHANNEL, 2, 8'bx, 16'bx);
      #2 sendChannelMessage(`CORE_MESSAGE_CREATE_CHANNEL, 2, 8'bx, 16'bx);
      #2 sendChannelMessage(`CORE_MESSAGE_ALT_START, 2, 8'bx, 16'bx);
      #2 sendChannelMessage(`CORE_MESSAGE_ENABLE_CHANNEL, 2, 0, 16'bx);
      #2 sendChannelMessage(`CORE_MESSAGE_ENABLE_CHANNEL, 2, 2, 16'bx);
      #2 sendChannelMessage(`CORE_MESSAGE_SEND, 4, 0, 10);
      if (!hasSchedulePidOut || schedulePidOut != 2) $error("Expected to schedule p2 after p4 sends to c0");
      if (!hasDeschedulePidOut || deschedulePidOut != 4) $error("Expected to deschedule p4");
      #2 sendChannelMessage(`CORE_MESSAGE_SEND, 6, 2, 20);
      if (hasSchedulePidOut) $error("Should not schedule p%0d", schedulePidOut);
      if (!hasDeschedulePidOut || deschedulePidOut != 6) $error("Expected deschedule p6");
      #2 sendChannelMessage(`CORE_MESSAGE_ALT_WAIT, 2, 8'bx, 16'bx);
      if (hasDeschedulePidOut) $error("Should not deschedule p%0d on alt wait", deschedulePidOut);
      #2 sendChannelMessage(`CORE_MESSAGE_DISABLE_CHANNEL, 2, 0, 16'bx);
      if (!hasSchedulePidOut || schedulePidOut != 4) $error("Should schedule p4");
      if (!rxHasMessageInAlt) $error("Should have message in alternation by now");
      #2 sendChannelMessage(`CORE_MESSAGE_DISABLE_CHANNEL, 2, 2, 16'bx);
      if (hasDeschedulePidOut) $error("Shouldn't have deschedule p%0d", deschedulePidOut);
      if (hasSchedulePidOut) $error("Shouldn't have schedule p%0d", schedulePidOut);
      if (!rxHasMessageInAlt) $error("Should have message in alternation by now");
      #2 sendChannelMessage(`CORE_MESSAGE_ALT_END, 2, 8'bx, 16'bx);
    end
  endtask

  initial begin
    $dumpfile("ChannelController_tb.vcd");
    $dumpvars(0, ChannelController_tb);

    #3 reset <= 1;
    #2 createChannelTest;
    #2 sendMessageTest;

    // Reset the heap and repeat the test
    #2 cc0.heap0.heapEnd <= 0;
    #2 createChannelTest;
    #2 sendMessageTest;
    #2 recvMessageTest;
    #2 freeChannelTest;

    #2 cc0.heap0.heapEnd <= 0;
    #2 createChannelTest;
    #2 recvFirstTest;
    #2 sendSecondTest;
    #2 freeChannelTest;

    #2 cc0.heap0.heapEnd <= 0;
       cc0.ram0.ram[0] <= 4;
    #2 createChannelTest;
    #2 enableChannelTest;
    #2 freeChannelTest;

    #2 altStartTest;
    #2 altWaitTest;
    #2 altEndTest;

    #2 cc0.heap0.heapEnd <= 0;
    #2 createChannelTest;
    #2 altStartTest;
    #2 sendMessageTest;
    #2 enableChannelTest;
    #2 altWaitNoDescheduleTest;
    #2 disableChannelTest;
    #2 altEndTest;
    #2 freeChannelTest;

    #2 alternationWithSendingAfterWaitTest;
    #2 alternationWithSendingBeforeWaitTest;

    #10 $finish;
  end
endmodule
