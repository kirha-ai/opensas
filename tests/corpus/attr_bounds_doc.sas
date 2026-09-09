/* ORACLE-unblocked-batch item 4 (GAP-attrprop-low-tick272 F8/F9) — the two
   attribute BOUNDS the SAS 9.4 DATA Step Statements: Reference actually states.
   Both page numbers were verified against the "=== pdf N ===" markers rather
   than taken from the board line, which named the entry TITLE pages (215/206)
   instead of the pages carrying the text (217/207) — the classic footer trap.

     LENGTH Statement, printed p.217 (marker "=== pdf 228 ==="; the footer
     "LENGTH Statement 217" closes that same pdf page):
       "length
          specifies a numeric constant for storing variable values. For numeric
          and character variables, this constant is the maximum number of bytes
          stored in the variable.
        Range  For numeric variables, 2 to 8 bytes or 3 to 8 bytes, depending
               on your operating environment. For character variables, 1 to
               32767 bytes under all operating environments.
        UNIX specifics  Numeric variables can range from 3 to 8 bytes."

     LABEL Statement, printed p.207 (marker "=== pdf 218 ==="; footer
     "LABEL Statement 207"):
       "text-string
          specifies a label of up to 256 bytes."

   This fixture pins ONLY the IN-RANGE boundaries, which opensas gets right:
   numeric 3 and 8, character 1 and 32767, and a label of exactly 256 bytes.
   The OUT-OF-RANGE lower bounds (`length n 2`, `length n 1`, `length n 0`,
   `length c $0`) are silently swallowed today and that is a real defect — it
   is written up in docs/findings/oracle-unblocked-readings.md item 4, NOT
   pinned here, because a red fixture would break the shared gate. When that
   lands, this file is the boundary guard that stops the new check from
   over-rejecting the legal edges. */
data numedge;
  length lo 3 hi 8;
  lo = 1; hi = 2;
run;
proc contents data=numedge; run;
data charedge;
  length one $1 big $32767;
  one = 'x'; big = 'y';
run;
proc contents data=charedge; run;
data lbl;
  length v $3;
  v = 'abc';
  label v = 'LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL';
run;
proc contents data=lbl; run;
