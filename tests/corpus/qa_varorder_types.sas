/* QA tick284 lock for BUG-varorder-setretain (40e503c). The fix pre-declares a
   RETAIN/sum var that PRECEDES the SET as a NUMERIC guess so it owns the earlier
   PDV slot (SAS first-mention order). This fixture locks the other half: that
   guess must NEVER survive — the SET source column's TYPE, LENGTH, FORMAT and
   LABEL still win. A refactor that stopped correcting the guess would silently
   turn character data numeric (data corruption, not a missing feature), and the
   order-only fixture var_order_setretain would not notice. */
data src;
  length name $20;
  label v='Value label';
  format v dollar8.2;
  input id name $ v;
datalines;
1 abcdefghijklmno 10
2 def 20
;
run;

/* name/v are retained BEFORE the set: they lead the column order, keep Char 20
   and DOLLAR8.2 + the label, and print their character values. */
data a; retain name v; set src; run;
proc contents data=a varnum; run;
proc print data=a; run;

/* 0-obs source: schema seeding must keep the same first-mention order. */
data e0; set src; stop; run;
data b; retain t 0 name; set e0; run;
proc contents data=b varnum; run;

/* A RETAIN naming a var no source has still creates it (missing), first. */
data c; retain ghost; set src(keep=id); run;
proc print data=c; run;
