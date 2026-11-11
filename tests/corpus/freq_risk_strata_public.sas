/* FEAT-freq-risk stratum isolation: public/freq_risk_strata_public SAS probe. */
options nodate nonumber; ods graphics off;
data cells; input stratum r c w; datalines;
1 1 1 12
1 1 2 8
1 2 1 5
1 2 2 25
2 1 1 4
2 1 2 6
2 2 1 8
2 2 2 2
;
proc freq data=cells; weight w; tables stratum*r*c / noprint senspec relrisk; run;
proc freq data=cells noprint; weight w; tables r / binomial(level=999); run;
