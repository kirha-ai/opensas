data have;
  input v;
  datalines;
3
1
2
2
;
run;

proc sort data=have out=desc; by descending v; run;

data _null_;
  set desc;
  by descending v;
  if first.v then put "FIRST " v=;
  if last.v  then put "LAST "  v=;
run;
