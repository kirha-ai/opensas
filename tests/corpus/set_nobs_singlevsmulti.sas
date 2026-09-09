/* QA tick154 regression guard (GAP-nobsmultisrc a2b9fca): the nobs= value must
   switch between the CURRENT source's count (single-source, nobs_total=null)
   and the a+b(+c) TOTAL (multi-source). The shipped set_nobs_multisrc.sas only
   locks the 2-source total; this pins single-source-unchanged AND 3-source so a
   future change can't collapse the branch either way. */
data a; input x; datalines;
1
2
3
;
run;
data b; input x; datalines;
4
5
;
run;
data c; input x; datalines;
6
;
run;
data _null_;
  set a nobs=n;        /* single source → 3 (unchanged) */
  if _n_=1 then put "single=" n;
run;
data _null_;
  set a b c nobs=n;    /* three sources → 3+2+1 = 6 total */
  if _n_=1 then put "multi=" n;
run;
