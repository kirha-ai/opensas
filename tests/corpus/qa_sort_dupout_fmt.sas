/* GREEN lock (qa tick231): PROC SORT DUPOUT= must carry the FULL column struct
   (format + label), not just name/type (BUG-sortinputopts dupout metadata).
   Also locks input where= filtering BEFORE the dedup so a filtered-out dup is
   never emitted to DUPOUT. */
proc format; value grp 1='One' 2='Two' 3='Three'; run;
data have;
  input k x;
  format x grp.;
  label x='X Label';
  datalines;
1 1
1 2
2 3
2 3
3 5
9 9
9 9
;
run;
/* where= keeps k<=3, then nodupkey by k; dups (k=1 second, k=2 second) go to d.
   k=9's dup must NOT appear in d (filtered out before dedup). */
proc sort data=have(where=(k<=3)) out=o nodupkey dupout=d; by k; run;
proc print data=o noobs; run;
/* DUPOUT dataset keeps x's format (grp.) and label */
proc print data=d label noobs; run;
proc contents data=d; run;
