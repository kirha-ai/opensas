data d; input g x; datalines;
1 10
1 20
2 30
;
run;
/* pctn/pctsum = cell share of the grand total (BUG-tabpctsum: was silently SUM);
   ALL = grand-total row (BUG-tabulateall: was silently dropped).
   g=1: n 2 of 3, sum 30 of 60 → 66.67% / 50%; All row = 100%. */
proc tabulate data=d; class g; var x; table g all, x*(n sum pctn pctsum); run;

data s; input reg $ prod $ amt; datalines;
E A 10
E B 20
W A 30
W B 40
;
run;
/* ALL in both dims of a 2-way cross: All column = row margin, All row = column
   margin, All×All = grand total. */
proc tabulate data=s; class reg prod; var amt; table reg all, prod*amt*sum all*amt*sum; run;
