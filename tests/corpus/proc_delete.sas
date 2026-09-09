/* PROC-delete: PROC DELETE drops named datasets (SAS between-step cleanup).
   Deleting an absent dataset warns (stderr) but never fail-louds, so the program
   keeps running; surviving datasets are untouched. */
data keep1; a=1; output; a=2; output; run;
data scratch; z=9; run;
data keep2; b=7; run;
proc delete data=scratch; run;
proc delete data=work.absent_ds; run;
data _null_; put "deletes done, still running"; run;
proc print data=keep1; run;
proc print data=keep2; run;
