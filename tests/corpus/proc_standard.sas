data d;
  input id v;
  datalines;
1 2
2 4
3 .
4 6
;
run;
/* z-scores: nonmissing {2,4,6}, n=3, mean=4, sample std=2 -> -1 0 . 1 */
proc standard data=d out=z mean=0 std=1;
  var v;
run;
proc print data=z noobs; run;
/* mean=100 std=15, REPLACE fills the missing with the target mean 100 */
proc standard data=d out=c mean=100 std=15 replace;
  var v;
run;
proc print data=c noobs; run;
/* BY groups with MEAN=/STD= omitted: each moment stays UNSET = the per-group
   sample mean/std -> output == input (BUG-stdnodefault) */
data g;
  input g v;
  datalines;
1 2
1 4
1 6
2 10
2 20
2 30
;
run;
proc standard data=g out=gz;
  var v;
  by g;
run;
proc print data=gz noobs; run;
