/* SAS 9.4 M9 produces the Missing Values table for an all-missing
   analysis variable, including when using a nonmissing WEIGHT variable.
   Each of the three observations counts once in both listings. */
data allmiss; input x w; datalines;
. 2
. 1
. 3
;
run;
proc univariate data=allmiss;
  var x;
run;
proc univariate data=allmiss;
  var x;
  weight w;
run;
