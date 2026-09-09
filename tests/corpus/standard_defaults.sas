/* BUG-stdnodefault: omitted MEAN= / STD= leave that moment UNSET = the BY
   group's sample mean/std, never forced to 0/1.
   {10,20,.,30,.}: mean 20, sample std 10. */
data d;
  input id v;
  datalines;
1 10
2 20
3 .
4 30
5 .
;
run;
/* classic mean-imputation idiom: originals kept, missings filled with the
   sample mean 20 -> 10 20 20 30 20 */
proc standard data=d out=imp replace;
  var v;
run;
proc print data=imp noobs; run;
/* MEAN=100 only: sample std 10 kept -> (x-20)/10*10+100 = x+80 -> 90 100 . 110 . */
proc standard data=d out=m100 mean=100;
  var v;
run;
proc print data=m100 noobs; run;
/* STD=5 only: sample mean 20 kept -> (x-20)/10*5+20 -> 15 20 . 25 . */
proc standard data=d out=s5 std=5;
  var v;
run;
proc print data=s5 noobs; run;
/* control: explicit MEAN=0 STD=1 -> z-scores -1 0 . 1 . (unchanged) */
proc standard data=d out=z mean=0 std=1;
  var v;
run;
proc print data=z noobs; run;
