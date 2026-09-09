data have;
  infile datalines dsd;
  input id $ val;
  datalines;
A B,10
x-1,20
1a,30
;
run;

proc transpose data=have out=want;
  id id;
  var val;
run;

/* V7-mangled names are referenceable: 'A B'->A_B, 'x-1'->x_1, '1a'->_1a */
data _null_;
  set want;
  put "A_B=" A_B " x_1=" x_1 " _1a=" _1a;
run;
