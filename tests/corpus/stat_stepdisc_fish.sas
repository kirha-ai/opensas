/* expect-rc: 1
 * STAT-STEPDISC-001: default PROC STEPDISC (METHOD=STEPWISE, SLENTRY= and
 * SLSTAY= 0.15) on the published SASHELP.FISH data with only a CLASS
 * statement: every numeric variable is a candidate, the observation with a
 * missing Weight is dropped (two WARNINGs, rc 1), entry by largest partial F
 * with the total-sample tolerance, Wilks/Pillai/ASCC per step and the
 * selection summary. Expected listing is the SAS 9.4 output, minus the blank
 * line SAS writes before the first page (opensas convention).
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title 'Fish Measurement Data';
proc stepdisc data=sashelp.fish;
class Species;
run;
