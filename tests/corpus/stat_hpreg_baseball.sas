/* STAT-HPREG-001: PROC HPREG least-squares fit without SELECTION of the
 * chapter's SASHELP.BASEBALL getting-started model with the
 * SELECTION statement removed: ID accepted, two CLASS variables in the GLM
 * parameterization, 59 observations with missing values excluded.
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) output of this program (summary
 * statistics only, no data rows).
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
proc hpreg data=sashelp.baseball;
id name;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError;
run;
