/* QA tick204: BREAK BEFORE and BREAK AFTER on the same group var, plus RBREAK
   BEFORE and AFTER, all with SUMMARIZE. The break-before rework (053dcb6) must
   coexist with the pre-existing after form: each region gets a subtotal row
   BEFORE its detail rows AND one AFTER; the grand total prints before all rows
   AND after all rows. Hand-verified: E units 1+2+3=6, W 4+5=9, grand 15/150. */
data sales;
  input reg $ prod $ units revenue;
  datalines;
E A 1 10
E A 2 20
E B 3 30
W A 4 40
W B 5 50
;
run;

proc report data=sales nowd;
  column reg prod units revenue;
  define reg / group;
  define prod / group;
  define units / analysis sum;
  define revenue / analysis sum;
  break before reg / summarize;
  break after reg / summarize;
  rbreak before / summarize;
  rbreak after / summarize;
run;
