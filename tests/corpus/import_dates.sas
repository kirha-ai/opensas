/* GAP-importtypes: PROC IMPORT's EFI detects date/time columns (Base SAS 9.4
   Procedures Guide, IMPORT chapter, printed p. 1330: a value a Date and Time
   format or numeric informat fits is declared NUMERIC, else character) — the
   column becomes NUMERIC with the matching format attached (p. 1340-41:
   JAN2001 → MONYY7.). A MIXED column and DOC-SILENT patterns (slash dates)
   stay character. The empty-file ERROR half is pinned by the captured-diag
   test in src/proc.zig (a failing step halts the run, so no stdout to pin). */
proc import datafile="tests/corpus/includes/import_dates.csv" out=imp dbms=csv replace;
  getnames=yes;
run;
proc contents data=imp varnum; run;
proc print data=imp noobs; run;
/* the read-back that proves the type: date arithmetic on the imported column
   (a char visit would fail char→num here, not just print differently) */
data _null_;
  set imp;
  dplus1 = visit + 1;
  since24 = visit - '01JAN2024'd;
  put dplus1 yymmdd10. +1 since24;
run;
