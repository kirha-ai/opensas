/* qa tick143 — verified-correct GREEN regression: PROC FREQ two-way crosstab
   with WEIGHT (freq/row-pct/col-pct/total math) and a WHERE stmt referencing a
   column named like a keyword ("id"), which PROC FREQ parses correctly (the
   keyword-as-identifier collision is PROC-PRINT/REPORT-specific, not FREQ).
   Every cell hand-checked vs SAS 9.4. */
data a; input id r $ c $ wt; datalines;
1 x p 3
2 x q 1
3 y p 2
4 y q 4
5 y q 1
;
run;
proc freq data=a; tables r*c; weight wt; where id<5; run;
