/* QA tick120: small odd-n (n=9) PROC UNIVARIATE — pins Definition-5 quantile
   interpolation at the boundaries (Q1/median/Q3) + moments on an explicit
   value list. Complements univar_large (n=5000 listing). Hand-verified:
   sorted 1,1,2,3,4,5,6,8,9 → Q1=2 (np=2.25→x3), Median=4 (x5), Q3=6 (np=6.75→x7),
   Min=1, Max=9; Mean=39/9=4.333..., N=9. */
data d; input x @@; datalines;
3 1 4 1 5 9 2 6 8
;
run;
proc univariate data=d; var x; run;
