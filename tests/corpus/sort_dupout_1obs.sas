/* DUPOUT= is materialized (0 obs, full schema) even for a 1-observation
   input — the dedup block must not skip it under its len>1 guard
   (BUG-sortdupoutfamily F3) */
data d; x=1; v=10; run;
proc sort data=d nodupkey dupout=dps out=o; by x; run;
proc print data=o; run;
proc print data=dps; run;
