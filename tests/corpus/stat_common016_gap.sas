/* expect-rc: 2
 * STAT-COMMON-016: a SURVEYMEANS statistic selection other than MEAN STDERR,
 * or MEAN STDERR CLM with or without NOBS, is not implemented; the step must fail visibly
 * (D-009 gap) without printing a listing. Invented data.
 */
data survey;
input stratum psu w y;
datalines;
1 1 1 4
1 2 2 6
2 3 1 7
2 4 2 9
;
proc surveymeans data=survey mean clm;
strata stratum; cluster psu; weight w; var y;
run;
