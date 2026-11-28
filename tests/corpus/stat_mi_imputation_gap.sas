/* expect-rc: 2
 * STAT-MI-001: imputation draws from the SAS random number stream and is
 * owned by later MI tickets; a step that imputes must fail visibly (D-009
 * gap) without printing a partial analysis or creating OUT=.
 * Invented data.
 */
data sizes;
input Height Weight;
datalines;
10 20
12 .
. 30
14 28
;
run;
proc mi data=sizes seed=42 nimpute=5 out=imputed;
var Height Weight;
run;
