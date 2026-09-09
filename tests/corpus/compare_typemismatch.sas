/* BUG-comparetypemismatch: a same-name variable that is NUMERIC in base but
   CHARACTER in compare is NOT value-compared (SAS requires matching types —
   coercing would call numeric 10 EQUAL to "10"); it is excluded and noted.
   BUG-comparedifsign: OUT= DIF/PCT use the SAS sign — Diff = comparison −
   base, PctDiff = Diff / base × 100. */
data b;
  input id x y $;
  datalines;
1 10 abc
2 20 def
;
run;
data c;
  input id x $ y $;
  datalines;
1 10 abc
2 30 xyz
;
run;
/* x is numeric in B, character in C → conflicting type, excluded (never a
   false EQUAL on 10 vs "10"); y is character both sides → compared. */
proc compare base=b compare=c;
  id id;
run;
/* SAS sign: base=10 compare=7 → DIF=-3, PCT=-30; base=20 compare=50 → +30/+150. */
data b2;
  input id v;
  datalines;
1 10
2 20
;
run;
data c2;
  input id v;
  datalines;
1 7
2 50
;
run;
proc compare base=b2 compare=c2 out=d outdif outpct;
  id id;
run;
proc print data=d;
run;
