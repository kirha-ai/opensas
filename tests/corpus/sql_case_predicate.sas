data lb;
  length usubjid $4;
  input usubjid $ aval;
  datalines;
S01 5
S02 .
S03 42
S04 18
;
run;
proc sql;
  create table flagged as select usubjid, aval,
    case when aval is missing then 'MISSING' else 'PRESENT' end as status,
    case when aval between 10 and 40 then 'NORMAL' else 'FLAG' end as grade
  from lb;
quit;
proc print data=flagged noobs; run;
