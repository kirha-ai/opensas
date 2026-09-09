/* BUG-informatlistinput: an INFORMAT statement in the SAME step as a list INPUT
   behaves like the `:` modifier (modified list input — a whitespace token), NOT
   a fixed-width column read. Was: `informat x $20.;` switched `input x $ y;`
   into a 20-column read that consumed the rest of the record and spilled the
   NEXT dataline into y — silently swallowing an obs (2 rows in, 1 out, and
   x held the whole line). Every dataline must be read; the LAST obs must be
   present. pi-xp noticed this while building xport_meta. */
data t;
  informat x $20.;
  input x $ y;
  datalines;
abc 5
def 6
;
run;

proc print data=t; run;

data _null_;
  set t end=last;
  put "ROW " x $char10. "y=" y;
  if last then put "LAST=[" x "]";
run;
