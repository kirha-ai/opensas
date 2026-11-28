/* STAT-CAUSALGRAPH-002: Getting Started analysis of the SAS/STAT 15.4
 * CAUSALGRAPH chapter (pp.2296-2298, published example): first step is the
 * documented default (METHOD=ADJUSTMENT, LIST implied by IDENTIFY; four
 * adjustment sets, one minimal of size 4). Later steps: the PSUMMARY display
 * option the Getting Started text names (p.2298), on the same model and on
 * invented small graphs: no-set NOTE, two models, NOLIST (no output), MAXLIST=
 * with MINIMAL, no IDENTIFY (no output). Expected listing: the SAS 9.4
 * reference listing of the documented default plus one SAS 9.4 reference run
 * of the PSUMMARY steps; the blank line SAS writes before each new page title
 * is dropped (opensas starts pages without it).
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
title 'P1';
proc causalgraph psummary;
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
title 'P2';
proc causalgraph psummary;
model "Small" Z ==> X, Z ==> Y, X ==> Y, W ==> Y;
identify X ==> Y;
run;
title 'P3';
proc causalgraph psummary;
model "NoSet" X ==> Y, U ==> X, U ==> Y;
identify X ==> Y;
unmeasured U;
run;
title 'P4';
proc causalgraph psummary;
model "A" Z ==> X, Z ==> Y, X ==> Y;
model "B" X ==> Y, W ==> X;
identify X ==> Y;
run;
title 'P5';
proc causalgraph psummary nolist;
model "Small" Z ==> X, Z ==> Y, X ==> Y;
identify X ==> Y;
run;
title 'P6';
proc causalgraph psummary maxlist=1 minimal;
model "Small" Z ==> X, Z ==> Y, X ==> Y, W ==> Y;
identify X ==> Y;
run;
title 'P7';
proc causalgraph psummary;
model "NoId" X ==> Y, Z ==> X;
run;
