/* NOTE-univallmiss: PROC UNIVARIATE on an ALL-MISSING analysis variable.
   Base SAS 9.4 Procedures Guide: Statistical Procedures, "Descriptive
   Statistics", printed p.410: the sum of the weights is Σwᵢ and "If there is no
   WEIGHT variable, the sum of the weights is n" — and n is computed whatever the
   missingness (Base SAS 9.4 Procedures Guide p.72: "N and NMISS do not require
   any nonmissing observations"). So N 0 must be paired with Sum Weights 0.

   Everything DERIVED FROM THE DATA stays missing, and that is CONFORMANT rather
   than a gap: Procedures Guide p.72 and p.2749 both say "SUM, MEAN, MAX, MIN,
   RANGE, USS, and CSS require at least one nonmissing observation" and
   "Statistics are reported as missing if they cannot be computed" — so Sum
   Observations, Uncorrected SS and Corrected SS print '.' next to Sum Weights 0.
   This fixture pins BOTH halves so a future "make the zeros consistent" edit
   cannot quietly zero the four that SAS leaves missing.

   Second PROC: the same with a WEIGHT variable whose weights are all present —
   every observation is still excluded for a missing x (p.408, "PROC UNIVARIATE
   excludes missing values for an analysis variable"), so Σwᵢ is the empty sum 0,
   not 2+1+3. */
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
