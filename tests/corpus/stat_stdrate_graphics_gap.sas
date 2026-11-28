/* expect-rc: 2
 * STAT-STDRATE-001: under ODS GRAPHICS ON the default direct rate analysis
 * also draws the stratum-specific rate plot, which is not implemented; the
 * step must fail visibly (D-009 gap) instead of printing tables without
 * the graph. Invented data.
 */
data study;
input age $ event total;
datalines;
young 10 1000
old 30 1500
;
data reference;
input age $ total;
datalines;
young 20000
old 10000
;
run;
ods graphics on;
proc stdrate data=study refdata=reference method=direct stat=rate;
population event=event total=total;
reference total=total;
strata age;
run;
