/* BUG-temparray-noretain: an UNINITIALIZED _TEMPORARY_ array is retained
   across DATA-step iterations in SAS 9.4 (always, inits or not) — the
   accumulation idiom depends on it; opensas reset uninited cells to missing
   each iteration. Expected final acc: 15 100 . */
data src;
  input cat val;
datalines;
1 10
1 5
2 100
;
run;

data _null_;
  array acc[3] _temporary_;
  set src end=last;
  acc[cat] = sum(acc[cat], val);
  if last then put acc[1] acc[2] acc[3];
run;
