/* BUG-meansstmtreplace: in PROC MEANS/SUMMARY a REPEATED VAR / CLASS / BY / ID
   statement REPLACES the prior one (SAS 9.4: last statement wins) — opensas used
   to APPEND, so `var a; var b;` analyzed BOTH a and b and `class x; class y;`
   kept both class vars (extra _TYPE_ levels). Step 1 must analyze ONLY b; step 2
   must group by ONLY y (one _TYPE_=1 level, no x levels); step 3 proves the
   one-statement multi-var form `var a b;` still analyzes both. */
data d;
  input a b x $ y $;
  datalines;
1 10 p u
2 20 q v
3 30 p v
;
run;

proc means data=d n mean sum;
  var a;
  var b;
run;

proc means data=d n mean;
  class x;
  class y;
  var a;
run;

proc means data=d n mean sum;
  var a b;
run;
