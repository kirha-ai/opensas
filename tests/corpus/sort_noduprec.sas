/* PROC SORT NODUPREC removes fully-identical rows; DUPOUT= captures the removed
   duplicates (NODUPKEY only dedups by key) — BUG-sortnoduprec */
data d;
  input id v;
  datalines;
1 10
1 10
1 20
2 30
2 30
;
run;
proc sort data=d out=nd noduprec dupout=dups;
  by id;
run;
data _null_; set nd; put "keep id=" id " v=" v; run;
data _null_; set dups; put "dup  id=" id " v=" v; run;
