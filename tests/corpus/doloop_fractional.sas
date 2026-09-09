/* DO-loop fractional increment (QA-tick127 regression): a naive `to`/`by`
   float accumulator stops one short of the endpoint because 0.1 repeated is
   slightly under 1.0. SAS fuzzes the boundary so `0 to 1 by 0.1` runs 11 times
   (includes the 1.0 iteration), and the loop variable prints as clean 0.1-step
   values, not 0.30000000000000004. Locks that behavior. */
data _null_;
  n=0;
  do i=0 to 1 by 0.1; n+1; end;
  put "count=" n;
  do x=0.1 to 0.5 by 0.1; put x=; end;
  /* descending fractional loop also hits its endpoint */
  m=0;
  do j=1 to 0 by -0.25; m+1; end;
  put "descn=" m;
run;
