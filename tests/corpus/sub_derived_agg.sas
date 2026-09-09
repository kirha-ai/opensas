data lb; length usubjid $4; input usubjid $ aval; datalines;
S01 10
S01 30
S02 20
S02 60
S03 15
;
run;
proc sql;
  create table overall as
    select max(mx) as max_of_max, avg(mx) as avg_of_max
    from (select usubjid, max(aval) as mx from lb group by usubjid);
quit;
proc print data=overall noobs; run;
