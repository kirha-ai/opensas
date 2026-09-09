/* BUG-sortinputopts: PROC SORT must honor INPUT dataset options
   (where=/keep=/drop=/rename=) BEFORE sorting, like every other PROC. */
data have;
  length grp $1;
  input grp $ x y z;
  datalines;
A 1 10 100
B 9 90 900
A 5 50 500
B 3 30 300
;
run;

/* input where= subsets rows and keep= drops columns, then sort by x */
proc sort data=have(where=(x>3) keep=grp x y) out=w; by x; run;
proc print data=w noobs; run;

/* input rename= a BY key: sorting must see the renamed column, in place */
data ren;
  input a b;
  datalines;
3 30
1 10
2 20
;
run;
proc sort data=ren(rename=(a=k)); by k; run;
proc print data=ren noobs; run;
