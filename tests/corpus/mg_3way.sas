data a;
  input id x;
  datalines;
1 10
2 20
;
run;

data b;
  input id y;
  datalines;
2 200
3 300
;
run;

data c;
  input id z;
  datalines;
1 1000
3 3000
;
run;

data m;
  merge a b c;
  by id;
run;

data _null_;
  set m;
  put "id=" id " x=" x " y=" y " z=" z;
run;
