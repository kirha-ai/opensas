/* QA tick120: PROC REPORT ORDER usage on a NUMERIC var — sorts ascending by
   underlying value (1,2,10 not lexical 1,10,2) and blanks repeated order values
   while listing every detail row. No GROUP → n is a per-row detail (sum of one
   obs = itself). Hand-verified order 1,2,2,10,10. */
data d; input k n; datalines;
10 1
2 2
10 3
1 4
2 5
;
run;
proc report data=d nowd;
  column k n;
  define k / order;
  define n / sum;
run;
