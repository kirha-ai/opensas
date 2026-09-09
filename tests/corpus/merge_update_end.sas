/* BUG-mergeupdateend: END= on MERGE and UPDATE was silently ignored (the var
   stayed ., and MERGE warned about a phantom "dataset  end=e not found").
   The `if e then` last-obs idiom must fire exactly once, on the final obs. */
data one;
  input id x;
  datalines;
1 10
2 20
3 30
;
run;

data two;
  input id y;
  datalines;
1 100
3 300
;
run;

data _null_;
  merge one two end=e;
  by id;
  if e then put "merge last id=" id " x=" x " y=" y;
  else put "merge row  id=" id;
run;

data trans;
  input id x;
  datalines;
2 25
4 40
;
run;

data _null_;
  update one trans end=e;
  by id;
  if e then put "update last id=" id " x=" x;
  else put "update row  id=" id;
run;

/* END= var is temporary: it must NOT land in the output dataset. */
data merged;
  merge one two end=e;
  by id;
run;
proc print data=merged noobs; run;
