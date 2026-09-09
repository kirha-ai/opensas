data src;
  input x;
  datalines;
1
2
3
4
;
run;

/* BUG-whereproc-half: a second plain WHERE REPLACES the first (SAS 9.4
   last-wins; mirrors DATA-step BUG-whereplacelast). The filter must be
   x < 4 (the LAST), not x > 1 — prints 1,2,3. */
proc print data=src noobs;
  where x > 1;
  where x < 4;
run;
