/* BUG-sqlemptycharaggtype: SQL Procedure Reference printed p.364 types
   string-arm CASE as character; pp.412-413 define MIN/MAX over an SQL
   expression, one group without GROUP BY, and missing for empty input.
   Printed p.373 represents character missing as blank, numeric missing as '.'.
   Explicit LENGTH=2 avoids relying on inferred character widths. */
data t;
  input x;
  datalines;
1
5
;
run;

proc sql;
  create table emptyagg as select
    min(case when x>3 then '9' else '10' end) as lo length=2,
    max(case when x>3 then '9' else '10' end) as hi length=2,
    min(case when x>3 then 9 else 10 end) as nlo,
    max(case when x>3 then 9 else 10 end) as nhi
    from t where x>100;
  create table grouped as select
    min(case when x>3 then '9' else '10' end) as lo length=2,
    max(case when x>3 then '9' else '10' end) as hi length=2,
    min(case when x>3 then 9 else 10 end) as nlo,
    max(case when x>3 then 9 else 10 end) as nhi
    from t where x>100 group by x;
  create table populated as select
    min(case when x>3 then '9' else '10' end) as lo length=2,
    max(case when x>3 then '9' else '10' end) as hi length=2,
    min(case when x>3 then 9 else 10 end) as nlo,
    max(case when x>3 then 9 else 10 end) as nhi
    from t;
quit;
proc contents data=emptyagg; run;
proc contents data=grouped; run;
data _null_;
  set emptyagg;
  lotype=vtype(lo); hitype=vtype(hi);
  nlotype=vtype(nlo); nhitype=vtype(nhi);
  loblank=(lo=''); hiblank=(hi='');
  lowidth=lengthc(lo); hiwidth=lengthc(hi);
  put lotype= hitype= nlotype= nhitype=;
  put loblank= hiblank= lowidth= hiwidth= nlo= nhi=;
run;
/* SQL reads the stored cells; DATA step SET also checks the descriptor. */
proc sql;
  select lo='' as loblank, hi='' as hiblank,
         lengthc(lo) as lowidth, lengthc(hi) as hiwidth
    from emptyagg;
quit;
data _null_;
  set populated;
  lotype=vtype(lo); hitype=vtype(hi);
  put lo= hi= nlo= nhi= lotype= hitype=;
run;
