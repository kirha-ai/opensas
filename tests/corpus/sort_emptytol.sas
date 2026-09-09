/* SORT-emptytol: PROC SORT tolerates absent/empty input — an absent dataset
   warns+skips and a 0-obs input is a no-op (nothing to reorder). A pipeline
   flows instead of dying, and a real sort still works. (The empty dataset is
   built with STOP, not a ghost SET — SET on a missing member is a hard error
   per BUG-setmissingquiet.) */
data have; input g $ v; datalines;
b 2
a 1
;
run;
proc sort data=ghost out=g1; by g; run;
data empt; stop; run;
proc sort data=empt; by g v; run;
proc sort data=have; by g v; run;
data _null_; put "pipeline survived"; run;
proc print data=have; run;
