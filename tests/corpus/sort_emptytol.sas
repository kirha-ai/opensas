/* SORT-emptytol: PROC SORT tolerates an EMPTY PRESENT input — a 0-obs dataset
   is a no-op sort (nothing to reorder) and a truly schemaless empty dataset
   (built with STOP, not a ghost SET: 0 rows AND 0 columns) has no columns to
   check a BY var against, so it stays tolerant without even validating `by`.
   The missing-MEMBER half of the old pin is GONE: SORT on an absent dataset
   is a hard ERROR since GH#8 ISS-sortmissingerr (the DATA-step SET has
   errored that identical shape all along — BUG-setmissingquiet), pinned now
   by sort_missingerr.sas. */
data have; input g $ v; datalines;
b 2
a 1
;
run;
data empt; stop; run;
proc sort data=empt; by g v; run;
proc sort data=have; by g v; run;
proc print data=have; run;
