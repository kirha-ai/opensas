/* Quantiles (Definition 5) must list all 11 rows: the 90% and 10% deciles
   were silently dropped. Regression for BUG-univquant9010. n=100, x=1..100:
   QNTLDEF=5 → p% = (x[np]+x[np+1])/2 when np integral, so 90% = 90.5,
   10% = 10.5. */
data d;
  do i = 1 to 100;
    x = i;
    output;
  end;
run;
proc univariate data=d;
  var x;
run;
