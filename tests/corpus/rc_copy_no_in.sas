/* DEC-abortrcvsD009 (2a57cc33, main.zig 618) — `proc copy` with no in= is the
   USER's SAS being wrong: real SAS 9.4 rejects it too ("The IN= option must be
   specified"), so D-009 says 1. It exited 2 ("file an opensas issue") until
   `failLoud` stopped doing double duty for both D-009 classes, and NOTHING in
   the tree could see the difference — BUG-nofixturepinsrc.
   The PROC PRINT first is deliberate: it makes the golden non-empty, so this
   fixture fails on both surfaces (stdout AND rc) rather than passing vacuously.
   expect-rc: 1 */
data a;
  x = 1;
run;
proc print data=a;
run;
proc copy out=work;
run;
