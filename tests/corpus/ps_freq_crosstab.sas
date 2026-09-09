data dm;
  length arm $1 sex $1;
  input arm $ sex $;
  datalines;
A M
A F
A M
B F
B F
B M
;
run;
proc freq data=dm; tables arm*sex; run;
