data have;
  input name $ val;
  datalines;
a 10
b 20
c 30
;
run;

proc transpose data=have out=want;
  id name;
  var val;
run;

data _null_;
  set want;
  put "a=" a " b=" b " c=" c;
run;
