data screened;
  length usubjid $4;
  input usubjid $;
  datalines;
S01
S01
S02
S02
S03
;
run;
data enrolled;
  length usubjid $4;
  input usubjid $;
  datalines;
S01
S02
;
run;
proc sql;
  /* EXCEPT ALL: screening records not matched one-for-one by enrollment */
  create table unenrolled_recs as select usubjid from screened except all select usubjid from enrolled;
  /* INTERSECT ALL: min multiplicity */
  create table matched_recs as select usubjid from screened intersect all select usubjid from enrolled;
quit;
proc print data=unenrolled_recs noobs; run;
proc print data=matched_recs noobs; run;
