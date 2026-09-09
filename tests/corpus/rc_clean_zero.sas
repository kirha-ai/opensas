/* The rc-0 rung of D-009, which nothing else pins. Every other expect-rc
   fixture asserts a NON-zero code, so a change that made the whole tree exit 1
   would leave them all green; this one holds the clean case down. Deliberately
   dull SAS — if this fixture ever fails, it is the exit path that broke, not
   the program.
   expect-rc: 0 */
data a;
  x = 1;
  y = 'ok';
run;
proc print data=a noobs;
run;
