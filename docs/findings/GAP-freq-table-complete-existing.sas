options nodate nonumber;
title 'Golden qa_freq_oneway_weighted_freqtie';
/* GREEN lock (qa tick231): one-pass hashed one-way FREQ (PERF-freqoneway).
   ORDER=FREQ with a WEIGHTED count tie must break by ASCENDING value, and
   non-positive/zero weights must not inflate a level. Locks the oneWayLevels
   accumulation + FreqCtx tie-break the perf refactor introduced. */
data t;
  input c $ wt;
  datalines;
b 3
a 2
c 4
a 1
b 0
c -5
d 3
b 0
;
run;
/* weighted counts: a=3, b=3, c=4, d=3 (b's two 0-wt rows keep level, add 0;
   c's -5 row excluded). order=freq: c(4) first, then a,b,d tie at 3 broken
   by ascending value -> a,b,d. */
proc freq data=t order=freq;
  tables c;
  weight wt;
run;

title 'Golden freq_nway_out';
data t;
  input a $ b $ c $;
  datalines;
a1 b1 c1
a1 b1 c2
a1 b2 c1
a1 b2 c2
a2 b1 c1
a2 b1 c1
a2 b2 c1
a2 b2 c2
;
run;

proc freq data=t;
  tables a*b*c;
run;

proc freq data=t noprint;
  tables a*b*c / out=f(rename=(count=count_));
run;

proc print data=f;
run;

title 'Golden freq_missing_strata';
data d;
  input g s $ r @@;
  datalines;
1 X 1  1 Y 0  . X 0  . X 1  2 Y 1  2 Y 0
;
run;

proc freq data=d;
  tables g*s*r;
run;

proc freq data=d;
  tables g*s*r / missing;
run;

title 'Golden note_freqfmtoutraw';
/* NOTE-freqfmtoutraw (qa tick191 F2): OUT= stores the RAW class value with the
   format ATTACHED — never the formatted label STRING (a descriptor must not
   disagree with the value it describes; a proc must not retype a column just
   because it carries a format). Pinned through three surfaces: PRINT still
   renders the labels, CONTENTS shows Num + the attached format, and a DATA-step
   read-back does ARITHMETIC on the class var — the surface that proves the
   type. The collapsed bf. arm proves SAS stores the LOWEST internal value of a
   format-combined group (Base SAS 9.4 Procedures Guide, PROC MEANS CLASS stmt
   Tip, printed p.1496). Siblings sharing the groupFormats rewrite are pinned
   too: SUMMARY (same builder), FREQ OUT= (own builder, same bug), UNIVARIATE
   (raw cells already; the format now attaches). The $cf. char-class control
   must not move: its raw value already is a string. */
proc format;
  value gf 1='One' 2='Two';
  value bf low-2='Low' 3-high='High';
  value $cf 'a'='Alpha' 'b'='Beta';
run;
data a;
  input g x @@;
  format g gf.;
  datalines;
1 10  1 20  2 30
;
run;
proc means data=a noprint;
  class g;
  var x;
  output out=o mean=m;
run;
proc print data=o; run;
proc contents data=o; run;
data b;
  set o;
  if _type_ = 1 then y = g * 10;
run;
proc print data=b; run;

data c;
  input g x @@;
  format g bf.;
  datalines;
1 10  2 20  3 30  4 40
;
run;
proc summary data=c noprint;
  class g;
  var x;
  output out=oc mean=m;
run;
proc contents data=oc; run;
data d2;
  set oc;
  if _type_ = 1 then y = g * 10;
run;
proc print data=d2; run;
proc freq data=c;
  tables g / out=of noprint;
run;
proc contents data=of; run;
data e;
  set of;
  y = g * 100;
run;
proc print data=e; run;

data h;
  input g $ x @@;
  format g $cf.;
  datalines;
a 10  a 20  b 30
;
run;
proc means data=h noprint;
  class g;
  var x;
  output out=oh mean=m;
run;
proc print data=oh; run;
proc contents data=oh; run;

proc univariate data=a noprint;
  class g;
  var x;
  output out=ou mean=mu;
run;
proc contents data=ou; run;

title 'Golden var_colon_prefix_freq_crossing';
/* GAP-freq-table-complete: supported table syntax regression. */
data t;
  x1 = 1; x2 = 2; y = 3;
run;
proc freq data=t;
  tables x:*y;
run;

title 'Golden freq_list_nway_gap';
/* GAP-freq-table-complete: supported table syntax regression. */
data d;
  input g h;
  datalines;
1 7
2 7
2 8
3 8
;
run;
proc freq data=d;
  tables g*h / list;
run;

title 'Golden freq_strata_order';
data d;
  input g $ s $ r @@;
  datalines;
Z X 1  Z X 1  Z Y 0  A Y 1  A Y 1
;
run;

/* Z has 3 obs, A has 2 → ORDER=FREQ lists Z's stratum first */
proc freq data=d order=freq;
  tables g*s*r;
run;

/* Z appears first in the data → ORDER=DATA lists Z's stratum first */
proc freq data=d order=data;
  tables g*s*r;
run;

/* default ORDER=INTERNAL: strata ascending (A then Z) */
proc freq data=d;
  tables g*s*r;
run;

