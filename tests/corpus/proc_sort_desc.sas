data have;
  input name $ age;
  datalines;
Alice 30
Bob 25
Carol 40
;
run;

proc sort data=have out=sorted;
  by descending age;
run;

data _null_;
  set sorted;
  put "name=" name " age=" age;
run;
