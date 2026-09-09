data master;
  input id v;
  datalines;
1 10
2 20
3 30
4 40
;
run;
/* REMOVE drops the current obs from the master in place; REPLACE rewrites it
   with the updated PDV; an untouched obs still gets the implicit REPLACE. */
data master;
  modify master;
  if id = 2 then remove;
  else if id = 3 then do;
    v = v + 100;
    replace;
  end;
run;
data _null_;
  set master;
  put "row " id= v=;
run;
