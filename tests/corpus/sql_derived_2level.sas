data lb;
  length usubjid $4 trt $1;
  input usubjid $ trt $ aval;
  datalines;
S01 A 10
S01 A 30
S02 A 20
S02 A 40
S03 B 50
S03 B 70
;
run;
proc sql;
  /* per-subject mean, then overall mean-of-means (canonical 2-level SDTM) */
  create table grand as
    select avg(subj_mean) as mean_of_means
    from (select usubjid, avg(aval) as subj_mean from lb group by usubjid);
  /* per-arm count of subjects via a derived per-subject table.
     NOTE: the inner GROUP BY has no summary function, so SAS treats it as an
     ORDER BY (all rows pass through — BUG-sqlgroupnoagg): n_subj counts ROWS
     per arm, not distinct subjects. Use DISTINCT in the inner select to dedup. */
  create table arm_n as
    select trt, count(*) as n_subj
    from (select usubjid, trt from lb group by usubjid, trt)
    group by trt;
quit;
proc print data=grand noobs; run;
proc print data=arm_n noobs; run;
