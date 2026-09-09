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
