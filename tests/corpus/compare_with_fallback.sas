/* BUG-comparewith (regression guard): when WITH has FEWER vars than VAR, the
   leading VAR[i]↔WITH[i] pair positionally and the trailing extra VAR falls
   back to same-name lookup in compare. Here var=x,y with=p → x↔p (positional,
   differs obs 2), y↔y (same-name fallback, equal). compare_with.sas only tests
   equal-length WITH; this pins the shorter-WITH fallback branch. */
data a; input id x y; datalines;
1 10 20
2 11 21
;
run;
data b; input id p y; datalines;
1 10 20
2 99 21
;
run;
proc compare base=a compare=b;
  var x y;
  with p;
run;
