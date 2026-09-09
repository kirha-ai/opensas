/* Completed vs boundary-crossing months (INTCK 'C' continuous vs 'D' discrete) */
data ae; input st : $9. en : $9.; datalines;
31JAN2020 28FEB2020
15JAN2020 15MAR2020
01JAN2024 31MAR2024
;
run;
data d;
  set ae;
  s = input(st, date9.);
  e = input(en, date9.);
  disc = intck("month", s, e, "d");
  cont = intck("month", s, e, "c");
run;
proc print data=d; var disc cont; run;
