/* BUG-badaritywrongtype: a wrong-arity call is a SAS ERROR, not a NOTE + a
   missing value the step keeps running past. Real SAS 9.4 rejects it at
   COMPILE time (oracle, sasrun 2026-10-31): `x=abs(1,2);` → "ERROR 72-185:
   The ABS function call has too many arguments."; `x=abs();` → "ERROR 71-185:
   The ABS function call does not have enough arguments." — the step never
   executes, rc nonzero. opensas checks arity at runtime dispatch, so the
   settled shape is the BUG-arrayoorerror one: the ERROR fires on the FIRST
   bad call and the step stops there. The ERROR is on stderr (asserted via
   captured diagnostics in functions.zig's test); stdout pins the HALT: the
   PUT after the bad call never runs, and a TOO-FEW call behaves the same.
   expect-rc: 1 */

data _null_;
  length a $5;
  put 'before';
  x = abs(1,2);    /* ERROR 72-185 class — the step stops HERE */
  put 'reached1';
  a = upcase('abc','x');
  put 'reached2';
run;

data _null_;
  y = abs();       /* ERROR 71-185 class: too few is the same abort */
  put 'too-few reached';
run;

data _null_;
  put 'skipped';   /* syntax-check mode (BUG-errhalt): skipped after the ERROR */
run;
