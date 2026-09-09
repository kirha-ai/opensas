/* BUG-inputmultirecmode: INFILE short-record modes (TRUNCOVER/MISSOVER) govern
   SHORT-record handling only — an EXPLICIT record advance (`/`, `#n`) must still
   move to the requested record (Language Reference: Concepts p.497 combines MISSOVER with 27 `/`). The
   one-record window clip blocked the advance, so every obs re-read the SAME
   record (`b` duplicated `a`) and the obs count doubled. Now the INPUT items are
   split at each advance and each segment reads its own one-record window: the
   advance works and the no-spill short-record rule applies per record. (no PHI) */
data tc;
  infile datalines truncover;
  input a $ /
        b $;
datalines;
A
B
C
D
;
run;
proc print data=tc noobs; run;

/* identical program without TRUNCOVER (default FLOWOVER) — was always correct */
data fl;
  infile datalines;
  input a $ / b $;
datalines;
A
B
C
D
;
run;
proc print data=fl noobs; run;

data mo;
  infile datalines missover;
  input a $ / b $;
datalines;
A
B
C
D
;
run;
proc print data=mo noobs; run;

/* #n line pointer under TRUNCOVER */
data hn;
  infile datalines truncover;
  input #1 a $ #2 b $;
datalines;
A
B
C
D
;
run;
proc print data=hn noobs; run;

/* short record + explicit advance together: rec 2 is short for `b c` (c missing,
   no spill), rec 4 is EMPTY mid-statement (b missing, must NOT pull rec 5's X).
   GAP-inputeofdegrade: there is NO third observation. Iteration 3 reads a=X from
   rec 5 and its `/` then asks for rec 6, which does not exist — Statements ref
   printed p.178 (footer "178 Chapter 2 / Dictionary of SAS DATA Step
   Statements"): "If a DATA step tries to read another record after it reaches an
   end-of-file, then execution stops." The step ends AT the INPUT, so the implicit
   OUTPUT never runs and the a=X row is not written. It used to be: the advance
   silently read an EMPTY record and the row went out with b and c missing — a
   fabricated observation at exit 0. The first two iterations, and the tc/fl/mo/hn
   blocks above, are unchanged: short-record handling is untouched, only the
   advance-past-EOF is. */
data sh;
  infile datalines truncover;
  input a $ / b $ c $;
datalines;
A
B
E

X
;
run;
proc print data=sh noobs; run;
