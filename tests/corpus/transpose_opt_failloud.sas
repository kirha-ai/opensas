/* BUG-transposeoptswallow: PROC TRANSPOSE used to swallow an unknown option or
   sub-statement with no diagnostic — a typo'd/bogus `zzz=1` vanished at rc=0
   (silent-noop). SAS 9.4 errors on an unrecognized option/statement; we must
   FAIL LOUD too (D-002, mirrors PROC SORT/COMPARE). The valid transpose below
   still pivots and prints; the 2nd proc prints nothing to stdout and reports
   the unknown option to stderr (non-zero exit). If the silent swallow
   regresses, the 2nd proc would append a pivot here and mismatch.
   "(non-zero exit)" is now PINNED at the exact number: `zzz=1` matches NO
   documented SAS 9.4 TRANSPOSE option (the closed set — Procedures Guide,
   7th ed., printed pp. 2697-2699 — is DATA=/DELIMITER=/INDB=/LABEL=/LET/
   NAME=/OUT=/PREFIX=/SUFFIX=), so it is a TYPO — the user's rc 1, not a gap
   (BUG-proctypoexits2; it was mis-pinned at 2 when the catch-all conflated
   the two). The rc-2 rung on this PROC is pinned by rc_transpose_option_gap.sas
   (INDB=, a documented option opensas doesn't implement), and tab_rowdim_failloud
   keeps the rung reachable tree-wide.
   expect-rc: 1 */
data d;
  input id $ x y;
  datalines;
A 10 100
B 20 200
;
run;
proc transpose data=d out=w prefix=pre_ name=src;
  id id;
  var x y;
run;
proc print data=w noobs; run;
proc transpose data=d out=w2 zzz=1;
  var x;
run;
