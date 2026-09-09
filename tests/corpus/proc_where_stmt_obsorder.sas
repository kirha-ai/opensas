/* BUG-procwherestmtorder: pins the Language Reference: Concepts p.229 rule
   that a PROC-level WHERE STATEMENT is a read-time filter applied BEFORE
   firstobs=/obs= count positions WITHIN the WHERE-selected subset — identical
   to the where= OPTION twin (BUG-whereobsorder) and the DATA-step statement
   twin (BUG-wherestmtobsorder). opensas sliced the physical firstobs=/obs=
   range first, THEN filtered, so a 100-row table with `where seq > 90` and
   (firstobs=2 obs=4) returned NOTHING where p.229 states the result is the
   2nd through 4th observations OF THE SUBSET (subset = rows 91-100, so rows
   92, 93, 94). */
data visits;
   do seq=1 to 100;
   score=seq + 1;
   output;
   end;
run;
proc print data=work.visits (firstobs=2 obs=4);
   where seq > 90;
run;

/* the where= OPTION spelling of the same query must agree row-for-row
   (both forms filter first; the slice counts within the subset) */
proc print data=work.visits (firstobs=2 obs=4 where=(seq>90)) noobs; run;

/* global `options firstobs=/obs=` + WHERE statement: same subset arithmetic */
options firstobs=2 obs=4;
proc print data=work.visits noobs;
   where seq > 90;
run;

/* the range alone, no WHERE: still the raw physical slice → rows 2,3,4 */
proc print data=work.visits noobs; run;
options firstobs=1 obs=max;
