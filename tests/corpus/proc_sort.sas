data have;
  input name $ age;
  datalines;
Carol 40
Alice 30
Bob 25
;
run;

proc sort data=have;
  by age;
run;

data _null_;
  set have;
  put "name=" name " age=" age;
run;
