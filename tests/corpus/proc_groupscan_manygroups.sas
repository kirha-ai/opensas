/* PERF-groupscan: hash-indexed CLASS/TABLES grouping must preserve output
   order (sorted by key) and values across many groups. */
data raw;
  do i = 1 to 30;
    g = mod(i, 5);
    v = i;
    output;
  end;
run;
proc means data=raw noprint nway;
  class g; var v; output out=m sum=sm n=cnt;
run;
data _null_; set m;
  put "g=" g " sum=" sm " n=" cnt;
run;
proc freq data=raw noprint; tables g / out=f; run;
data _null_; set f;
  put "g=" g " count=" count " pct=" percent;
run;
