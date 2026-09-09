/* D-022 (BUG-xstmtsilentnoop): X is still inert — `somedir/sub` is NOT created —
   but the mid-step X below now emits `NOTE: X statement not executed …` on
   stderr. This golden is stdout-only, so it is unchanged; the NOTE text is
   pinned by the captured-reporter test in src/parser.zig and the rc-0 /
   step-continues half by x_dm_note.sas. */
libname mylib "somedir";
data _null_;
  x mkdir "somedir/sub";
  msg = "step still runs";
  put msg;
run;
