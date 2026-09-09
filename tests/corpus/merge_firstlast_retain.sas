data a;
  input id v;
  datalines;
1 100
1 101
2 200
3 300
3 301
;
run;
data b;
  input id w;
  datalines;
1 10
2 20
3 30
;
run;
data out;
  merge a b;
  by id;
  retain cnt 0;
  if first.id then cnt=0;
  cnt+1;
  if last.id then output;
run;
proc print data=out noobs; run;
