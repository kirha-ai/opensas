/* BUG-univclassrawgroup (HIGH silent-wrong): PROC UNIVARIATE grouped CLASS by
   the RAW value where SAS — and our own PROC MEANS — group by the FORMATTED
   value (Base SAS 9.4 Procedures Guide, PROC MEANS CLASS stmt Tip, printed
   p.1497: "To reduce the number of class variable levels, use a FORMAT
   statement to combine variable values. When a format combines several
   internal values into one formatted value, PROC MEANS outputs the lowest
   internal value." — the Tip's premise is that a collapsing format REDUCES
   the number of levels). On gg. below UNIVARIATE emitted FOUR groups
   (Low/Low/High/High, n=1 each, the same label printed twice) where there
   are two, so every per-class statistic was computed over the wrong
   partition. The fix makes UNIVARIATE the fourth groupFormats consumer (with
   MEANS/SUMMARY/FREQ) — this fixture pins UNIVARIATE and MEANS SIDE BY SIDE
   on the same data with the same collapsing format, so the two can never
   diverge again.
   Surfaces pinned: the OUT= rows (PRINT renders the labels), the OUT=
   descriptor (CONTENTS: g stays Num 8 with GG. ATTACHED — not a Char label
   string, NOTE-freqfmtoutraw), a DATA-step ARITHMETIC read-back (g*10 = 10
   for Low, 30 for High: the stored cell is the LOWEST raw of the group), the
   LISTING per-class blocks (two blocks, raw-value order Low then High, and
   composing with BY), a CHARACTER class with a collapsing $fmt., and a
   non-collapsing format as the control (one level per raw, unchanged). */
proc format;
  value gg 1-2='Low' 3-4='High';
  value gf 1='One' 2='Two';
  value $cf 'a'='AB' 'b'='AB' 'c'='C';
run;

data a;
  input g x @@;
  format g gg.;
  datalines;
1 10  2 20  3 30  4 40
;
run;

proc univariate data=a noprint;
  class g;
  var x;
  output out=u n=n mean=m;
run;

proc means data=a noprint;
  class g;
  var x;
  output out=mo n=n mean=m;
run;

proc print data=u; run;
proc print data=mo; run;
proc contents data=u; run;

data rb;
  set u;
  y = g * 10;
run;

proc print data=rb; run;

/* The LISTING side partitions the same way: two blocks (Low then High,
   raw-value order as the MEANS listing), n=2 per level, not four. */
proc univariate data=a;
  class g;
  var x;
run;

/* CLASS x BY composition (BUG-univignoresby landed the BY arm): per BY
   group, the same two formatted levels. */
data ab;
  input b g x @@;
  format g gg.;
  datalines;
1 1 10  1 2 20  1 3 30  1 4 40  2 1 50  2 4 60
;
run;

proc univariate data=ab noprint;
  by b;
  class g;
  var x;
  output out=abu n=n mean=m;
run;

proc print data=abu; run;

/* CHARACTER class with a collapsing $fmt. — same rule: 'a' and 'b' share
   the label AB, so two levels; OUT= keeps Char + $CF. attached and stores
   the lowest raw ('a' sorts before 'b', so AB stores 'a'). */
data c;
  input g $ x @@;
  format g $cf.;
  datalines;
a 10  b 20  c 30
;
run;

proc univariate data=c noprint;
  class g;
  var x;
  output out=cu n=n mean=m;
run;

proc contents data=cu; run;
proc print data=cu; run;

/* the stored cell is the lowest RAW ('a'), not the label string 'AB' —
   the char twin of the g*10 read-back above */
data crb;
  set cu;
  if g = 'a' then hit = 1;
  else hit = 0;
run;

proc print data=crb; run;

/* Non-collapsing control: one formatted level per raw value — the partition
   is unchanged (gf. maps 1:1), proving only COLLAPSING groups merge. */
data nc;
  input g x @@;
  format g gf.;
  datalines;
1 10  1 20  2 30
;
run;

proc univariate data=nc noprint;
  class g;
  var x;
  output out=nu n=n mean=m;
run;

proc print data=nu; run;

/* A proc-level FORMAT statement overrides the stored format for the
   grouping (the groupFormats stmt_specs rule MEANS already runs): gf.
   collapses nothing on `a`, so four one-obs levels — and MEANS agrees. */
proc univariate data=a noprint;
  class g;
  format g gf.;
  var x;
  output out=ovu n=n;
run;

proc means data=a noprint;
  class g;
  format g gf.;
  var x;
  output out=ovm n=n;
run;

proc print data=ovu; run;
proc print data=ovm; run;
