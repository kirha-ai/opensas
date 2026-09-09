/* BUG-meansoutbydescending (tick364 F1): PROC MEANS/UNIVARIATE OUTPUT OUT=
   used to sort its summary rows ASCENDING even under BY DESCENDING — a
   dataset our own next DATA step (`set s; by descending g;`) then REFUSED to
   read ("BY variables are not properly sorted"), while the listing, PRINT,
   TRANSPOSE, RANK and TABULATE all emitted descending in the same run. The
   OUT= rows now go out in the BY's own direction (the per-key directions
   decodeProcBy already returns). The Procedures Guide is SILENT on OUT= row
   order (its BY chapter, p.74-75, only says BY "orders the output according
   to the BY groups" and defines DESCENDING per key), so this pin is
   consistency-driven: the ROUND TRIP below is the whole point — the OUT=
   dataset must be readable by a step with the identical BY, at exit 0.
   Ascending-BY OUT= output is byte-identical to before (re-sort fires only
   when a key descends). */

data d;
  input g x;
  datalines;
3 7
2 10
2 20
1 5
1 15
1 25
;
run;

/* 1. The bug: OUT= under BY DESCENDING must come back largest-first. */
proc means data=d noprint;
  by descending g;
  var x;
  output out=s mean=m n=n;
run;

proc print data=s noobs;
run;

/* 2. The round trip: our own DATA step with the IDENTICAL BY must accept the
      dataset we just wrote (was: ERROR "not properly sorted", exit != 0). */
data z;
  set s;
  by descending g;
run;

proc print data=z noobs;
run;

/* 3. UNIVARIATE shares the builder — same rule. */
proc univariate data=d noprint;
  by descending g;
  var x;
  output out=u mean=um;
run;

proc print data=u noobs;
run;

/* 4. Mixed-direction multi-variable BY: g ascending, h descending within g. */
data m;
  input g h x;
  datalines;
1 2 10
1 1 20
2 2 30
2 1 40
;
run;

proc means data=m noprint;
  by g descending h;
  var x;
  output out=sm mean=mm;
run;

proc print data=sm noobs;
run;

data zm;
  set sm;
  by g descending h;
run;
