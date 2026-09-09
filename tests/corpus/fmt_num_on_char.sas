/* NOTE-fmtnumoncharcoerce: a NUMERIC format on a CHARACTER variable is a SAS
   compile-time ERROR — Formats & Informats Ref printed p.7 ("The FORMAT
   statement permanently associates character variables with character formats
   and numeric variables with numeric formats") + p.5 (an incompatible format
   falls back to an analogous format of the other type, else an ERROR message —
   never a silent coerce). It used to print '.' for 'abc' with exit 0.
   Sections are ordered: the controls and the value-level fallbacks produce
   stdout; the compile-time errors (DATA-step FORMAT, PROC FORMAT, ATTRIB —
   asserted loud in src/exec.zig's NOTE-fmtnumoncharcoerce test) halt/skip, so
   they come last and print nothing.
   THE rc PIN THAT MATTERS: this is the one file out of 1874 whose exit code
   moved when 2a57cc33 corrected the six wrong-rc sites (2 -> 1, stdout
   IDENTICAL), and no fixture could notice — BUG-nofixturepinsrc. Now one can.
   expect-rc: 1 */

/* control that must NOT move: numeric format on numeric, $ format on char */
data ctrl;
  length c $3;
  c = 'abc';
  n = 5;
  format n dollar8. c $8.;
run;
proc print data=ctrl; run;

/* value level (PUT spec): the mismatch is LOUD on stderr and renders the raw
   text (the p.5 analogous-format fallback) — 'abc' is NOT destroyed to '.' */
data _null_;
  c = 'abc';
  put c 8.2;
run;

/* mirror at value level: numeric value under a $ format, raw text too */
data _null_;
  n = 5;
  put n $8.;
run;

/* PROC-step FORMAT statement mismatch — loud BEFORE the table, nothing prints */
proc print data=ctrl;
  format c 8.2;
run;

/* DATA-step FORMAT statement mismatch — compile-time ERROR; the step halts
   with 0 obs and every later step is syntax-check-skipped (BUG-errhalt), so
   this must stay the last section */
data bad;
  length c $3;
  c = 'abc';
  format c 8.2;
run;
proc print data=bad; run;
