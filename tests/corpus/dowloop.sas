/* DOWLOOP-impl: a SET inside a DO UNTIL/WHILE (a "DOW loop"). SAS 9.4 reads the
   NEXT obs at the inner SET each DO iteration, accumulates across the BY group,
   and outputs once per outer DATA-step pass. Synthesized (no PHI). */
data sales; input grp amt; datalines;
1 10
1 20
1 5
2 30
2 40
3 7
;
run;

/* sum amt per grp via DOW: read until last.grp, accumulate, output one row/group */
data sums;
  do until(last.grp);
    set sales; by grp;
    if first.grp then total = 0;
    total + amt;
  end;
  output;
run;

proc print data=sums; run;

/* whole-dataset sum via `do until(eof)` with end= */
data grand;
  do until(eof);
    set sales end=eof;
    g + amt;
  end;
  output;
run;

proc print data=grand; run;
