data d;
  input name $ age @@;
  datalines;
Ann 30 Bob 25 Cy 40
;
run;
data _null_; set d; put "name=" name " age=" age; run;
