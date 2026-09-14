/* GAP-sysparm-opt: ONE session value behind all three documented surfaces —
   `options sysparm="text";`, the SYSPARM() function, and the &SYSPARM
   automatic (Macro Reference printed pp.486-487: valid in the OPTIONS
   statement). Before this fix the OPTIONS statement errored "system option
   sysparm is not recognized" while SYSPARM() returned "" and &sysparm seeded
   "". Default with no option: "". The &SYSPARM reference lives in a step
   AFTER the first `run;`: a chunk's macro expansion runs before its
   statements execute, so the next chunk is the first point where the
   OPTIONS write is visible (live read — macro.zig getVar). */
options sysparm="PROBE123";
data _null_;
  sp = sysparm();
  put "FUNCTION=[" sp "]";
run;
data _null_;
  mv = "&sysparm";
  put "MACRO=[" mv "]";
run;
options sysparm="";
data _null_;
  reset = sysparm();
  put "RESET=[" reset "]";
run;
