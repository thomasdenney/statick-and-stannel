`include "defaults.vh"

module Scheduler_tb();
  localparam addrBits = `ADDRESS_BITS;
  localparam dataBits = `DATA_BITS;

  reg clk = 0;
  always #1 clk <= ~clk;

  reg reset = 0;
  reg enabled = 0;
  wire finished;

  reg core0ReadyForDeschedule;
  reg core1ReadyForDeschedule;

  reg                hasDeschedule;
  reg [addrBits-1:0] deschedulePid;
  reg                hasSchedule;
  reg [addrBits-1:0] schedulePid;

  reg                core0Active;
  reg [addrBits-1:0] core0Pid;
  reg                core1Active;
  reg [addrBits-1:0] core1Pid;
  reg                core0NeedsResumeAwake;
  reg                core1NeedsResumeAwake;

  wire canHalt;

  Scheduler #(.addrBits(addrBits), .dataBits(dataBits)) scheduler (
    .clk                    (clk),
    .reset                  (reset),
    .enabled                (enabled),
    .finished               (finished),

    .core0ReadyForDeschedule(core0ReadyForDeschedule),
    .core1ReadyForDeschedule(core1ReadyForDeschedule),

    .hasDeschedule          (hasDeschedule),
    .deschedulePid          (deschedulePid),
    .hasSchedule            (hasSchedule),
    .schedulePid            (schedulePid),

    .core0Active            (core0Active),
    .core0Pid               (core0Pid),
    .core1Active            (core1Active),
    .core1Pid               (core1Pid),
    .core0NeedsResumeAwake  (core0NeedsResumeAwake),
    .core1NeedsResumeAwake  (core1NeedsResumeAwake),

    .canHalt                (canHalt)
  );

  task schedule1;
    begin
      enabled                 <= 1;
      core0ReadyForDeschedule <= 1;
      core1ReadyForDeschedule <= 1;
      hasDeschedule           <= 0;
      hasSchedule             <= 1;
      schedulePid             <= 1;

      @(posedge finished)
        begin
          enabled <= 0;
          if (!core0Active) $error("Expected core 0 to be active");
          if (!core0NeedsResumeAwake) $error("Need to awaken core 0");
          if (core0Pid != schedulePid) $error("Expected core 0 to be assigned %0d", schedulePid);
          if (core1Active) $error("Core 1 should not be active");
          if (core1NeedsResumeAwake) $error("Core 1 should not need a resume");
          if (canHalt) $error("Shouldn't be able to halt");
        end
    end
  endtask

  task schedule2;
    begin
      hasSchedule <= 1;
      schedulePid <= 2;
      enabled     <= 1;

      @(posedge finished)
        begin
          enabled <= 0;
          if (!core0Active) $error("Core 0 should be active");
          if (core0NeedsResumeAwake) $error("Core 0 shouldn't be resumed");
          if (core0Pid != 1) $error("Core 0 should have pid 1");
          if (!core1Active) $error("Core 1 should be active");
          if (!core1NeedsResumeAwake) $error("Core 1 should need resume awake");
          if (core1Pid != schedulePid) $error("Expected core 1 to be assigned %0d", schedulePid);
          if (canHalt) $error("Shouldn't be able to halt");
        end
    end
  endtask

  task schedule3;
    begin
      hasSchedule <= 1;
      schedulePid <= 3;
      enabled     <= 1;

      @(posedge finished)
        begin
          enabled <= 0;
          if (!core0Active) $error("Core 0 should be active");
          if (core0NeedsResumeAwake) $error("Core 0 shouldn't be resumed");
          if (core0Pid != 1) $error("Core 0 should have pid 1");
          if (!core1Active) $error("Core 1 should be active");
          if (core1NeedsResumeAwake) $error("Core 1 should need resume awake");
          if (core1Pid != 2) $error("Expected core 1 to be assigned 2");
          if (canHalt) $error("Shouldn't be able to halt");
        end
    end
  endtask

  task deschedule1;
    begin
      hasDeschedule <= 1;
      hasSchedule <= 0;
      deschedulePid <= 1;
      enabled <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (!core0Active) $error("Core 0 should be active");
          if (!core0NeedsResumeAwake) $error("Core 0 should need resume");
          if (core0Pid != 3) $error("Core 0 should have pid 3");
          if (!core1Active) $error("Core 1 should be active");
          if (core1NeedsResumeAwake) $error("Core 1 shouldn't need resume awake");
          if (core1Pid != 2) $error("Expected core 1 to be assigned 2");
          if (canHalt) $error("Shouldn't be able to halt");
        end
    end
  endtask

  task deschedule2Schedule4;
    begin
      hasDeschedule <= 1;
      hasSchedule <= 1;
      deschedulePid <= 2;
      schedulePid = 4;
      enabled <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (!core0Active) $error("Core 0 should be active");
          if (core0NeedsResumeAwake) $error("Core 0 shouldn't need resume");
          if (core0Pid != 3) $error("Core 0 should have pid 3");
          if (!core1Active) $error("Core 1 should be active");
          if (!core1NeedsResumeAwake) $error("Core 1 needs resume awake");
          if (core1Pid != 4) $error("Expected core 1 to be assigned 4");
          if (canHalt) $error("Shouldn't be able to halt");
        end
    end
  endtask

  task deschedule3;
    begin
      hasDeschedule <= 1;
      hasSchedule <= 0;
      deschedulePid <= 3;
      enabled <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (core0Active) $error("Core 0 shouldn't be active");
          if (core0NeedsResumeAwake) $error("Core 0 shouldn't need resume");
          if (!core1Active) $error("Core 1 should be active");
          if (core1NeedsResumeAwake) $error("Core 1 needs resume awake");
          if (core1Pid != 4) $error("Expected core 1 to be assigned 4");
          if (canHalt) $error("Shouldn't be able to halt");
        end
    end
  endtask

  task deschedule4;
    begin
      hasDeschedule <= 1;
      deschedulePid <= 4;
      enabled <= 1;
      @(posedge finished)
        begin
          enabled <= 0;
          if (core0Active) $error("Core 0 shouldn't be active");
          if (core0NeedsResumeAwake) $error("Core 0 shouldn't need resume");
          if (core1Active) $error("Core 1 should be active");
          if (core1NeedsResumeAwake) $error("Core 1 needs resume awake");
          if (!canHalt) $error("Shouldn't be able to halt");
        end
    end
  endtask
  initial begin
    $dumpfile("Scheduler_tb.vcd");
    $dumpvars(0, Scheduler_tb);

    #2 reset <= 1;
    #4 schedule1;
    #4 schedule2;
    #4 schedule3;
    #4 deschedule1;
    #4 deschedule2Schedule4;
    #4 deschedule3;
    #4 deschedule4;

    #4 $finish;
  end

endmodule
