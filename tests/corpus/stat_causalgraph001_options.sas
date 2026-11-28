/* STAT-CAUSALGRAPH-001: explicit basic options on the Getting Started model
 * of the SAS/STAT 15.4 CAUSALGRAPH chapter (published example, pp.2296-2297).
 * NOPRINT suppresses all displayed output (p.2302). MAXSIZE=4 keeps only the
 * size-4 set and MAXLIST=ALL / NTHREADS=2 / explicit LIST and
 * METHOD=ADJUSTMENT leave the listing otherwise unchanged (pp.2300-2302), so
 * the expected listing is the SAS 9.4 reference listing of the default run
 * with adjustment sets 2-4 (sizes 5 and 6) removed.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
proc causalgraph noprint;
model "Timm17TwoLatent"
Age ==> Parity PFAS Education, Parity ==> PrevBF Duration PFAS,
PrevBF ==> PFAS Duration, PFAS ==> Duration,
Education ==> Duration Employment PFAS BMI Alcohol Smoking,
Employment ==> Duration PFAS BMI Alcohol Smoking, BMI Alcohol Smoking ==> Duration;
identify PFAS ==> Duration;
unmeasured Alcohol Smoking;
run;
proc causalgraph list method=adjustment maxsize=4 maxlist=all nthreads=2;
model "Timm17TwoLatent"
Age ==> Parity PFAS Education, Parity ==> PrevBF Duration PFAS,
PrevBF ==> PFAS Duration, PFAS ==> Duration,
Education ==> Duration Employment PFAS BMI Alcohol Smoking,
Employment ==> Duration PFAS BMI Alcohol Smoking, BMI Alcohol Smoking ==> Duration;
identify PFAS ==> Duration;
unmeasured Alcohol Smoking;
run;
