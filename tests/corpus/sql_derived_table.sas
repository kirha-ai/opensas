data lb;
  length subjid $4;
  input subjid $ val;
  datalines;
S001 10
S001 30
S002 20
S002 40
S003 5
;
run;
proc sql;
  create table agg as
    select subjid, mx
    from (select subjid, max(val) as mx from lb group by subjid) as t
    where mx > 15;
  create table dcount as
    select count(*) as n from (select distinct val from lb) as u;
  create table overall as
    select max(mx) as maxmax
    from (select subjid, max(val) as mx from lb group by subjid);
quit;
proc print data=agg noobs; run;
proc print data=dcount noobs; run;
proc print data=overall noobs; run;
