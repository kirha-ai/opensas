%let n = 3;
%let name = Bob;

data _null_;
  put "n=&n name=&name";
run;
