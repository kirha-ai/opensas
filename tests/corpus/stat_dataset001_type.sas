/* STAT-DATASET-001: the TYPE= data set attribute (S154 pp.10880-10881).
 * TYPE= on a DATA statement output is recorded uppercase (any name, never
 * rewritten), an ordinary data set has a blank TYPE, a DATA step SET does not
 * copy TYPE=, PROC SORT OUT= keeps it, PROC CONTENTS shows "Data Set Type".
 * Expected values from a SAS 9.4 run of the same steps (CONTENTS in opensas's
 * established compact CONTENTS layout). Invented data.
 */
options nodate nonumber nocenter;
data a; input x y; datalines;
1 2
3 5
4 4
;
data c(type=corr); _type_='CORR'; _name_='x'; x=1; y=0.5; output; _name_='y'; x=0.5; y=1; output; run;
data d; set c; run;
data e(type=mytyp); set a; run;
proc sort data=c out=s; by x; run;
data _null_;
  file print;
  length t $16;
  array m{5} $8 _temporary_ ('a' 'c' 'd' 'e' 's');
  do k = 1 to 5;
    h = open(m{k}); t = attrc(h, 'TYPE'); n = attrn(h, 'NOBS'); rc = close(h);
    mem = m{k}; tq = cats('[', t, ']'); put @1 mem $1. @3 tq $8. @12 n 1.;
  end;
run;
proc contents data=c; run;
