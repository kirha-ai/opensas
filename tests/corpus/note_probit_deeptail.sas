/* NOTE-probitdeeptail (PARKED): pins the PROBIT accuracy rule from the
   Functions Reference (p.1332), which states no accuracy guarantee — only
   Range 0<p<1 (loud domErr here) and a CAUTION that the result could be
   truncated to [-8.222, 7.941]. So the deep tail is not a conformance
   question. This fixture pins the accuracy opensas DOES have, to catch
   regressions:
   - the two reference quantiles printed on p.1332 (p=0.025 and p=1e-7) match
     to all 10 printed digits;
   - p=1e-10 is pinned at the CURRENT value, known 1.54e-9 relative off the
     true quantile (-6.361340902404056) — a behaviour pin, not a doc claim. */
data _null_;
  q_lo=probit(0.025);
  q_tail=probit(1.e-7);
  q_deep=probit(1e-10);
  q_mid=probit(0.5);
  /* STAT-BEST-001: BEST32. shows at most 16 characters besides the sign, so
     q_tail is printed with BEST12. = the 10 digits the reference prints
     (-5.199337582). SAS 9.4 itself returns -5.19933758219281 at BEST32.,
     4.2e-11 from opensas's -5.199337582150739: a known accuracy difference,
     reported separately, not pinned here. deep_tail keeps the opensas
     behaviour pin -6.361340912201716, shown by the SAS BEST32. rule as
     -6.36134091220171 (SAS 9.4 prints the same text for that double). */
  put "ref_quantiles=" q_lo best32. q_tail best12.;
  put "deep_tail=" q_deep best32.;
  put "median=" q_mid best32.;
run;
