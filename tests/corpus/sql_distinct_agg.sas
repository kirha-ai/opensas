/* BUG-sqldistinctagg: SUM/AVG(DISTINCT) must dedup before aggregating; plain
   SUM/AVG and COUNT(DISTINCT) unchanged, incl. per-group dedup. */
data t;
  input g y;
  datalines;
1 2.5
1 2.5
1 3.75
1 1.25
1 4.0
2 1.0
2 1.0
2 1.0
;
run;
proc sql;
  create table u as
    select sum(distinct y) as sd, avg(distinct y) as ad, count(distinct y) as cd,
           sum(y) as s, avg(y) as a, count(y) as c
    from t;
quit;
data _null_; set u; put "sd=" sd " ad=" ad " cd=" cd " s=" s " a=" a " c=" c; run;
proc sql;
  create table gp as
    select g, sum(distinct y) as sd, avg(distinct y) as ad, count(distinct y) as cd,
           sum(y) as s
    from t group by g;
quit;
data _null_; set gp; put "g=" g " sd=" sd " ad=" ad " cd=" cd " s=" s; run;
