/* REOPEN-meansdefvar (tick212 F3 / tick156 #3): with NO VAR statement, PROC
   MEANS analyzes every numeric variable EXCEPT those named in CLASS/BY/
   FREQ/WEIGHT/ID. Here g is CLASS — it must NOT get an "Analysis Variable : g"
   table; only the other numeric x is analyzed, per CLASS level. Verified
   against SAS 9.4 semantics: the default analysis set excludes any variable
   another statement claimed. */
data d;
  input g x;
  datalines;
1 10
1 20
2 30
2 40
;
run;
proc means data=d;
  class g;
run;
