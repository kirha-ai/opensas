/* FEAT-freq-exact CL=EXACT integration. SAS 9.4 M9 cl-regression.sas,
   2026-11-13: RD columns [.1145,.6675] and [-.6675,-.1145].
   Full exact numerical acceptance remains pending; this fixture is now supported. */
options nodate nonumber; ods graphics off;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=t; weight w; tables r*c / riskdiff(cl=exact); exact riskdiff; run;
