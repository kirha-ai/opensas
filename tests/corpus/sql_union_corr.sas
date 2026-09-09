data t1;
  input a b c;
  datalines;
1 10 100
2 20 200
2 20 200
;
run;

data t2;
  input b c d;
  datalines;
20 200 7
30 300 8
;
run;

/* UNION CORRESPONDING: only columns named in BOTH selects (b, c), aligned by
   name in first-select order, deduped like plain UNION. */
proc sql;
  create table uc as
    select a, b, c from t1
    union corr
    select b, c, d from t2;
  create table uac as
    select a, b, c from t1
    union all corr
    select b, c, d from t2;
  create table ec as
    select a, b, c from t1
    except corr
    select b, c, d from t2;
  create table ic as
    select a, b, c from t1
    intersect corr
    select b, c, d from t2;
quit;

data _null_;
  set uc;
  put "uc b=" b " c=" c;
run;

data _null_;
  set uac;
  put "uac b=" b " c=" c;
run;

data _null_;
  set ec;
  put "ec b=" b " c=" c;
run;

data _null_;
  set ic;
  put "ic b=" b " c=" c;
run;
