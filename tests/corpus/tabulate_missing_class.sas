/* BUG-tabulatemissclass: SAS 9.4 EXCLUDES an obs with a missing value on ANY
   class variable from the whole table — every cell N/SUM and every PCTN
   denominator — by DEFAULT; the MISSING option keeps such obs as their own
   class level (missing numeric sorts first, blank char first). opensas kept
   them in every N/SUM/PCTN and silently swallowed the MISSING option.
   (MEANS/FREQ already exclude on the same binary — BUG-meansclassmiss.) */
data d; input g x; datalines;
1 10
1 20
. 999
2 30
;
run;
/* default: the g=. obs is dropped — denominator is 3, so g=1 is N=2 Sum=30
   PctN=66.67 and g=2 is N=1 Sum=30 PctN=33.33; no g=. row. */
proc tabulate data=d; class g; var x; table g, x*(n sum pctn); run;
/* MISSING: g=. is its own level, ordered first — N=1 Sum=999 PctN=25 (of 4). */
proc tabulate data=d missing; class g; var x; table g, x*(n sum pctn); run;

/* blank CHAR class level: same default exclusion, same MISSING re-include
   (the blank level prints as an empty label, ordered first). */
data c;
  input g $ x;
  if x = 40 then g = ' ';
  datalines;
A 10
A 20
B 30
Z 40
;
run;
proc tabulate data=c; class g; var x; table g, x*(n sum pctn); run;
proc tabulate data=c missing; class g; var x; table g, x*(n sum pctn); run;

/* 2-way cross: default drops an obs missing on EITHER class var (the reg=.
   E-row's amt 30 and the prod=. W-row's amt 40 vanish); MISSING keeps both as
   blank levels, ordered first on their axis. */
data x2;
  input reg $ prod $ amt;
  if amt = 30 then reg = ' ';
  if amt = 40 then prod = ' ';
  datalines;
E A 10
E B 20
Q A 30
W Q 40
W B 50
;
run;
proc tabulate data=x2; class reg prod; var amt; table reg, prod*amt*sum; run;
proc tabulate data=x2 missing; class reg prod; var amt; table reg, prod*amt*sum; run;
