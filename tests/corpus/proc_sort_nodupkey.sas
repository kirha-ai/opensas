data have;
  input name $ age;
  datalines;
Bob 25
Alice 30
Bob 25
Alice 99
;
run;

proc sort data=have out=u nodupkey;
  by name;
run;

data _null_;
  set u;
  put "name=" name " age=" age;
run;
