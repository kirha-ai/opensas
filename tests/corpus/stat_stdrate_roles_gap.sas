/* expect-rc: 2
 * STAT-STDRATE-001: METHOD=INDIRECT with REFERENCE EVENT=, a STRATA SMR
 * request and BY parse and validate, but indirect standardization and its
 * listing are not implemented; the step must fail visibly (D-009 gap)
 * without printing a partial analysis. Invented data.
 */
data study;
input site age $ event total;
datalines;
1 young 10 1000
1 old 30 1500
;
data reference;
input age $ event total;
datalines;
young 100 20000
old 150 10000
;
run;
proc stdrate data=study refdata=reference method=indirect stat=rate;
population event=event total=total;
reference event=event total=total;
strata age / smr;
by site;
run;
