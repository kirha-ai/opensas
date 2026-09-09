/* BUG-setstmtorder regression net: a DOW loop (SET nested in a top-level
   DO UNTIL) is NOT a direct top-level driver, so it keeps node-driven
   reads (DOWLOOP-impl) — the statement-order split must not touch it.
   One output row per BY group with the group sum accumulated across the
   inner reads. */
data a; input k v; datalines;
1 10
1 20
2 30
2 40
3 50
;
run;
data dow; do until(last.k); set a; by k; s + v; end; run;
proc print data=dow noobs;
   title 'DOW loop: one row per BY group';
run;
