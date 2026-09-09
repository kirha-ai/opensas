/* Multi-ID PROC TRANSPOSE with the SAS-DEFAULT delimiter (no DELIMITER=): the
   two ID values are joined by `_` (SAS default), and because the raw name would
   start with a digit SAS prepends `_` -> _1_1, _1_2, _2_1. The first ID (r=1)
   REPEATS across rows (1,1) and (1,2); concatenating the second ID keeps the
   column names distinct, so there is NO spurious "ID value occurs twice" error.
   transpose_multiid.sas only covers a custom DELIMITER=X; this locks the
   default-`_` path (regression bank, QA tick128). */
data have;
  input grp r c y;
  datalines;
1 1 1 10
1 1 2 20
1 2 1 30
;
run;
proc transpose data=have out=want;
  by grp;
  id r c;
  var y;
run;
proc print data=want noobs; run;
