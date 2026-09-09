data _null_;
  input id 1-3 name $ 4-11 age 13-14;
  put "id=" id " name=[" name "] age=" age;
  datalines;
001John     42
002Mary     37
;
run;
