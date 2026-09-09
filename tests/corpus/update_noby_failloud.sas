/* BUG-updatenoby: UPDATE (and MODIFY) with a transaction dataset but NO BY
   statement used to collapse all rows into one artificial group and apply
   transactions positionally — arbitrary, silent-wrong output on a common
   user error. SAS 9.4 errors "The BY statement is required for the UPDATE
   statement" and produces no dataset. The valid UPDATE-with-BY below proves
   transactions still apply (a `.` in the transaction leaves the master value
   intact); the no-BY step then fails LOUD — ERROR to the log, no dataset, no
   stdout (per BUG-errhalt later steps are skipped after a step ERROR). If the
   guard regresses, a bogus positional-update listing appears here and
   mismatches.
   expect-rc: 1 */
data master;
  input id x y;
  datalines;
1 10 100
2 20 200
;
run;
data trans;
  input id x y;
  datalines;
2 . 250
;
run;
data good;
  update master trans;
  by id;
run;
proc print data=good noobs; run;
data bad;
  update master trans;
run;
proc print data=bad noobs; run;
