/* PROC SQL OUTER UNION set operator.
   SAS 9.4 SQL Procedure, "Combining Queries with Set Operators": OUTER UNION
   concatenates ALL rows of both queries and, WITHOUT CORRESPONDING, keeps ALL
   columns of both (it does NOT overlay same-named columns or align by position
   — that is plain UNION). Each input row fills only its own query's columns;
   the other columns are missing. OUTER UNION CORR (CORRESPONDING) overlays
   same-named columns (align by name) while still concatenating every row. */
data one;
  input a b;
  datalines;
1 2
3 4
;
run;
data two;
  input c d;
  datalines;
5 6
;
run;
data three;
  input a x;
  datalines;
7 9
;
run;
/* plain OUTER UNION: 4 columns a b c d, 3 rows, non-source columns missing */
proc sql;
  create table u as select a, b from one outer union select c, d from two;
quit;
proc print data=u noobs; run;
/* OUTER UNION CORR: same-named `a` overlaid, `b` and `x` distinct -> cols a b x */
proc sql;
  create table uc as select a, b from one outer union corr select a, x from three;
quit;
proc print data=uc noobs; run;
