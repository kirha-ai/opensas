data s;
  input a b c;
  datalines;
1 2 3
4 5 6
;
run;
proc sql;
  create table t (a num, b num, c num);
  insert into t (c, b, a) select a, b, c from s;
quit;
proc print data=t noobs; run;
proc sql;
  create table u (a num, b num, c num);
  insert into u select a, b, c from s;
quit;
proc print data=u noobs; run;
