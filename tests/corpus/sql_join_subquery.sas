/* Inline view (subquery) in a JOIN — GH#14 ISS-sqljoinsubquery.
   1) simple `inner join (select …) b on …`
   2) min-date-per-subject idiom: join a group-by aggregate subquery. */
data ec;
  length subjid $4;
  input subjid $ ecdtc :$10.;
  datalines;
S001 2020-01-05
S001 2020-01-02
S002 2020-03-10
S002 2020-03-01
S003 2020-06-15
;
run;

proc sql;
  /* simple inline-view join: keep rows whose subject appears in the subquery */
  create table t1 as
    select a.subjid, a.ecdtc
    from ec a
      inner join (select subjid from ec) b on a.subjid = b.subjid
    order by a.subjid, a.ecdtc;

  /* min-date-per-subject via a group-by subquery joined back to ec */
  create table firstdose as
    select a.subjid, a.ecdtc
    from ec a
      inner join (select subjid, min(ecdtc) as mindtc from ec group by subjid) b
        on a.subjid = b.subjid and a.ecdtc = b.mindtc
    order by a.subjid;
quit;

proc print data=t1 noobs; run;
proc print data=firstdose noobs; run;
