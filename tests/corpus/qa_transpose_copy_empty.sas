/* BUG-transposecopyempty (QA tick284 F3): PROC TRANSPOSE + COPY on a 0-row
   input (here a where= that matches nothing) indexed row 0 of the empty table
   and the process ABORTED (SIGABRT, 21/4000 fuzz hits). A crash is never
   acceptable: the output must be the same one all-missing row the no-COPY
   empty case already emits — _NAME_ plus the COPY columns, char and numeric
   both missing. */
data e; input c $ k v; datalines;
a 2 3
;
run;
proc transpose data=e(where=(k>99)) out=t2; copy c k; var v; run;
proc print data=t2; run;
