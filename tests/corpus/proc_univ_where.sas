/* BUG-univwherestmt — WHERE is documented WITH PROC UNIVARIATE ("Procedures
   That Support the WHERE Statement", Procedures Guide printed p. 89) but the
   statement loop errored rc 1 on it. Now accepted and applied (N=2, not 3). */
data have;
  input name $ age;
  datalines;
Carol 40
Alice 30
Bob 25
;
run;
proc univariate data=have;
  where age>28;
  var age;
run;
