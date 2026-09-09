/* BUG-univreport: the default PROC UNIVARIATE report was silently PARTIAL —
   only Moments + Quantiles printed. SAS 9.4 also emits Basic Statistical
   Measures, Tests for Location: Mu0=0, and Extreme Observations.
   Hand-verified (independent Python, exact enumeration for signed-rank):
   n=9 mean=43/9=4.77777778 std=4.35252162 var=18.94444444 sem=1.45084054
   t=3.29311020 df=8 p=0.0110; sign M=(8-1)/2=3.5 p=2*P(Bin(9,.5)>=8)=20/512=0.0391;
   signed-rank S=18.5 (ranks of |x|, tie {3,3} averaged) exact p=14/512=0.0273;
   mode=3 (twice), median=5, IQR=8-3=5, range=14; skew=-0.87097809 kurt=0.80961267.
   Extremes: lowest -4(1) 2(2) 3(3) 3(4) 5(5), highest 10(9)..5(5) — n<10 so the
   two sides overlap, and the {3,3} tie pins ties-in-data-order on the lowest side. */
data d; input x @@; datalines;
-4 2 3 3 5 7 8 9 10
;
run;
proc univariate data=d; var x; run;
