/* GAP-gapsexitingone §5c — the unknown-CALL-routine catch-all was SPLIT.

   CALL COMPCOST has its own entry in the SAS 9.4 Functions and CALL Routines
   reference, so it is valid SAS opensas has not written: an opensas GAP →
   rc 2. rc_call_routine_typo.sas pins the other arm — a MISSPELLED routine
   name stays rc 1, because telling a user who typed `call symptu(...)` to
   file an opensas issue is exactly the failure this contract exists to stop.

   The PROC PRINT proves the split discriminates: the implemented CALL
   routines beside it still run. One error, last (BUG-errhalt).
   expect-rc: 2 */
data got;
  length s $ 20;
  x = 1;
  call missing(x);
  s = "a";
  call cats(s, "b", "c");
  call symputx("m", "set");
  n = 2;
run;

proc print data=got noobs;
run;

data _null_;
  call compcost("a", "b", 1);
run;
