/* STAT-CAUSALGRAPH-001: PROC CAUSALGRAPH default listings (VariableInfo,
 * GraphicalModelSummary, AdjustList by the default METHOD=ADJUSTMENT with
 * LIST implied by IDENTIFY). First step: the Getting Started model of the
 * SAS/STAT 15.4 CAUSALGRAPH chapter (pp.2296-2297, published example). Later
 * steps: invented small graphs covering no IDENTIFY (NOLIST default), the
 * empty adjustment set, no valid set (NOTE in the listing), COMPACT with
 * MINIMAL, MAXSIZE=MIN with MAXLIST=, alternative arrow spellings, and a
 * graph without covariates (DATA= is accepted and ignored). The expected
 * listing is SAS 9.4 reference runs of these steps; the blank line SAS writes
 * before each new page title is dropped (opensas starts pages without it).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
proc causalgraph;
model "Timm17TwoLatent"
Age ==> Parity PFAS Education,
Parity ==> PrevBF Duration PFAS,
PrevBF ==> PFAS Duration,
PFAS ==> Duration,
Education ==> Duration Employment PFAS BMI Alcohol Smoking,
Employment ==> Duration PFAS BMI Alcohol Smoking,
BMI Alcohol Smoking ==> Duration;
identify PFAS ==> Duration;
unmeasured Alcohol Smoking;
run;
title 'case1';
proc causalgraph; model 'A' X ==> Y, Z ==> X Y; run;
title 'case2';
proc causalgraph; model 'B' X ==> Y, Z ==> Y, W ==> X; identify X ==> Y; run;
title 'case3';
proc causalgraph; model 'C' X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; run;
title 'case4';
proc causalgraph compact minimal; model 'B' X ==> Y, Z ==> Y, W ==> X, V ==> X Y; identify X ==> Y; run;
title 'case5';
proc causalgraph maxsize=min maxlist=2; model 'B' X ==> Y, Z ==> Y, W ==> X, V ==> X Y; identify X ==> Y; run;
title 'case12';
proc causalgraph; model 'H' X --> Y, Z => X, Y <-- W, M -> Y; identify X > Y | Z; run;
title 'case13';
proc causalgraph data=sashelp.class; model 'H' X ==> Y; identify X ==> Y; run;
