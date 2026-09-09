/* BUG-meansbyunsorted: PROC MEANS/SUMMARY BY on an UNSORTED input used to
   silently POOL the out-of-order groups — the OUT= dataset merged the two
   non-adjacent g='a' obs into one row and the listing printed the g='a'
   section twice. SAS 9.4 ERRORs "Data set X is not sorted in ascending
   sequence" and stops: no dataset, no listing. The sorted MEANS below proves
   per-group stats (listing AND OUT=) are unchanged; the unsorted step then
   fails LOUD — ERROR to the log, no stdout (per BUG-errhalt later steps are
   skipped after a step ERROR). If the guard regresses, a pooled 2-row OUT=
   listing / duplicated g='a' section appears here and mismatches.
   rc PINNED at 1: this is the SURVIVING TWIN of the PROC PRINT site that
   2a57cc33 corrected — the identical ERROR line exited 1 here and 2 there
   (see rc_print_by_unsorted.sas, which pins the other end). */
/* expect-rc: 1 */
data s;
  input g $ v;
  datalines;
a 1
a 3
b 2
b 4
;
run;
proc means data=s;
  by g;
  var v;
run;
proc means data=s noprint;
  by g;
  var v;
  output out=o n=cnt mean=m;
run;
proc print data=o noobs; run;

data u;
  input g $ v;
  datalines;
a 1
b 2
a 3
;
run;
proc means data=u noprint;
  by g;
  var v;
  output out=bad n=cnt mean=m;
run;
proc print data=bad noobs; run;
