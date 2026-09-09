/* FEAT-procreport rest4: `_c<n>_` absolute column references in a COMPUTE
   expression — reference a report column by its 1-based COLUMN-list position.
   Here _c1_ and _c2_ are columns a and b; the computed column mixes an absolute
   ref with a named ref to prove they compose. */
data d;
  input a b;
  datalines;
1 10
2 20
3 30
;
run;

proc report data=d nowd;
  column a b tot;
  define a / display;
  define b / display;
  define tot / computed;
  compute tot;
    tot = _c1_ * 100 + b;
  endcomp;
run;
