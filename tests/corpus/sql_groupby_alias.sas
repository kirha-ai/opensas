data lb;
  length usubjid $4;
  input usubjid $ age aval;
  datalines;
S01 25 10
S02 45 20
S03 68 30
S04 34 40
S05 71 50
S06 52 60
;
run;
proc sql;
  /* group by a computed age band via its SELECT alias */
  create table byband as
    select case when age < 40 then 'Young' when age < 65 then 'Mid' else 'Old' end as band,
           count(*) as n, avg(aval) as mean
    from lb
    group by band;
  /* group by an arithmetic alias, and by position */
  create table byparity as select mod(age,2) as parity, count(*) as n from lb group by calculated parity;
quit;
proc print data=byband noobs; run;
proc print data=byparity noobs; run;
