/* Enrolled INTERSECT / EXCEPT dosed subject sets */
data a; input v; datalines;
1
2
3
4
;
run;
data b; input v; datalines;
2
4
6
;
run;
proc sql;
  select v from a intersect select v from b order by v;
  select v from a except select v from b order by v;
quit;
