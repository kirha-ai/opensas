/* FEAT-callexecute: CALL EXECUTE queues FULL steps that run AFTER the current
   step, FIFO across invocations; queued text may hold multiple steps. Order
   below proves it: main-before/main-after (current step) first, then the
   queued DATA step's PUT, then the queued PROC PRINT. */
data _null_;
  put "main-before";
  call execute('data _null_; put "queued-first"; run;');
  call execute('data q2; x=42; run; proc print data=q2; run;');
  put "main-after";
run;
