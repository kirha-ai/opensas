/* expect-rc: 2
 * STAT-MIANALYZE-001: PARMS= input data sets, CLASS effects, TEST, the
 * covariance displays and the BY-group listing are not implemented; each
 * step must fail visibly (D-009 gap) without printing a partial analysis.
 * Invented data.
 */
data fits;
input grp Intercept SeInt;
datalines;
1 90.5 9.0
1 94.0 8.5
2 96.5 9.5
2 89.0 8.0
;
run;
proc mianalyze data=fits;
modeleffects Intercept;
stderr SeInt;
by grp;
run;
proc mianalyze parms=fits;
modeleffects Intercept;
run;
proc mianalyze data=fits tcov;
modeleffects Intercept;
stderr SeInt;
run;
