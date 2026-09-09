/* BUG-setvarretain narrowed by BUG-setsourcereset: driver-SET source columns
   are retained WITHIN a source, but the PDV's SET variables RESET at a source
   switch — Language Reference: Concepts p.562 Execution Step 2: "The values of the variables in the
   program data vector are then set to missing, and SAS begins reading
   observations from the second data set"; p.563: "The values of variables
   found in one data set but not in another are set to missing."  (PROC APPEND
   must "produce the same results as concatenation", p.564, and it blanks.)
   `set a b;` — y lives only in a, so on b's obs it is MISSING (an earlier
   revision of this fixture pinned y=10 — the bleed bug itself); x is in both,
   so each read overwrites it; z is a plain data-step var (not SET-read), so
   it resets to missing.  The conditional/extra SET retention this ticket was
   really about (`if _n_=1 then set b;`) is pinned by multiset.sas. */
data a;
  x = 1; y = 10;
run;
data b;
  x = 2;
run;
data _null_;
  set a b;
  if _n_ = 1 then z = 99;
  put x= y= z=;
run;
