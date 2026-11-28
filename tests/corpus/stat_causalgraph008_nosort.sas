/* STAT-CAUSALGRAPH-008 (Time Requirements, PDF pp.2330-2331): the NOSORT
 * and MAXLIST= requests the section names. Expected listing: six batched SAS
 * 9.4 reference runs of these steps (2026-11-28), page-start blank lines
 * dropped as in other titled fixtures; one TESTID step (pre-existing title
 * centering difference, STAT-CAUSALGRAPH-005) left out. Invented graphs;
 * the first steps use the Getting Started graph of p.2297.
 * Rules shown: NOSORT lists in exclusion-first order (MAXLIST=m keeps the
 * last m sets after MINIMAL/MAXSIZE= filtering); NOSORT MINIMAL lists the
 * minimal sets in inclusion-first order; NOSORT MAXLIST=1 reports the direct
 * search set An(X u Y u prescribed) over the allowed covariates (also for
 * METHOD=BACKDOOR), then MAXSIZE= may drop it; MINIMAL MAXLIST=1 the first
 * minimal set; MAXSIZE=MIN and METHOD=IV ignore NOSORT; more than 20
 * covariates (25 confounders, 22 free covariates) are listed; tables wider
 * than LINESIZE= narrow their column gaps. The 2^13 and 2^15-set sorted
 * steps (V2, V4) took SAS 3.05 s and 14.45 s real time against 0.00 s and
 * 0.01 s for NOSORT MAXLIST=5 (V1, V3).
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote; ods graphics off;
title 'CASE a1';
proc causalgraph nosort maxlist=2 maxsize=1;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE a2';
proc causalgraph nosort maxlist=2;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE a3';
proc causalgraph nosort maxlist=3;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE b1';
proc causalgraph nosort maxlist=2;
model 'D' X ==> M, M ==> Y, Z ==> X Y, X ==> D, A ==> Z, A ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE b2';
proc causalgraph method=backdoor nosort maxlist=1;
model 'Q' X ==> M, M ==> Y, Z ==> X Y Q, X ==> D, A ==> Z, A ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE b3';
proc causalgraph method=adjustment nosort maxlist=1;
model 'Q' X ==> M, M ==> Y, Z ==> X Y Q, X ==> D, A ==> Z, A ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE b4';
proc causalgraph method=backdoor nosort;
model 'Q' X ==> M, M ==> Y, Z ==> X Y Q, X ==> D, A ==> Z, A ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE c1';
proc causalgraph nosort;
model 'MM' X ==> Y, A ==> X B, B ==> Y, C ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE c2';
proc causalgraph ;
model 'MM' X ==> Y, A ==> X B, B ==> Y, C ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE c3';
proc causalgraph nosort minimal;
model 'MM' X ==> Y, A ==> X B, B ==> Y, C ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE c4';
proc causalgraph nosort maxlist=1 minimal;
model 'MM' X ==> Y, A ==> X B, B ==> Y, C ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE c5';
proc causalgraph nosort maxlist=1;
model 'MM' X ==> Y, A ==> X B, B ==> Y, C ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE c6';
proc causalgraph nosort maxlist=2;
model 'MM' X ==> Y, A ==> X B, B ==> Y, C ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE c7';
proc causalgraph nosort maxsize=min;
model 'MM' X ==> Y, A ==> X B, B ==> Y, C ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE c8';
proc causalgraph nosort maxlist=2 maxsize=2;
model 'MM' X ==> Y, A ==> X B, B ==> Y, C ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE d1';
proc causalgraph nosort minimal;
model 'M3' X ==> Y, A ==> X B, B ==> Y, C ==> X D, D ==> Y, E ==> X F, F ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE d2';
proc causalgraph minimal;
model 'M3' X ==> Y, A ==> X B, B ==> Y, C ==> X D, D ==> Y, E ==> X F, F ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE d3';
proc causalgraph nosort maxlist=3;
model 'M3' X ==> Y, A ==> X B, B ==> Y, C ==> X D, D ==> Y, E ==> X F, F ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE d4';
proc causalgraph nosort;
model 'M3' X ==> Y, A ==> X B, B ==> Y, C ==> X D, D ==> Y, E ==> X F, F ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE e1';
proc causalgraph nosort maxlist=1 nolist;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE e2';
proc causalgraph nosort maxlist=1;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
model 'T' X ==> Y, Z ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE f1';
proc causalgraph nosort minimal;
model 'M5' X ==> Y, Q ==> X, Z ==> Q Y X R, R ==> Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE f2';
proc causalgraph minimal;
model 'M5' X ==> Y, Q ==> X, Z ==> Q Y X R, R ==> Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE f3';
proc causalgraph nosort maxlist=2 minimal;
model 'M5' X ==> Y, Q ==> X, Z ==> Q Y X R, R ==> Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE f4';
proc causalgraph nosort maxlist=1 minimal;
model 'M5' X ==> Y, Q ==> X, Z ==> Q Y X R, R ==> Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE f5';
proc causalgraph nosort;
model 'M5' X ==> Y, Q ==> X, Z ==> Q Y X R, R ==> Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE f6';
proc causalgraph nosort maxlist=1;
model 'M5' X ==> Y, Q ==> X, Z ==> Q Y X R, R ==> Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE f7';
proc causalgraph method=backdoor nosort minimal;
model 'M5' X ==> Y, Q ==> X, Z ==> Q Y X R, R ==> Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE f8';
proc causalgraph nosort minimal maxsize=2;
model 'M5' X ==> Y, Q ==> X, Z ==> Q Y X R, R ==> Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE g1';
proc causalgraph nosort maxsize=min nolist;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE g2';
proc causalgraph nosort maxsize=min noprint;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE g3';
proc causalgraph nosort method=iv nolist;
model 'V' I ==> X, X ==> Y, U ==> X Y;
identify X ==> Y;
unmeasured U;
run;
quit;

title 'CASE g4';
proc causalgraph nosort maxlist=1 maxsize=min;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE g5';
proc causalgraph nosort maxlist=1 maxsize=min method=iv;
model 'V' I ==> X, X ==> Y, U ==> X Y;
identify X ==> Y;
unmeasured U;
run;
quit;

title 'CASE g6';
proc causalgraph nosort maxlist=1;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y | V;
run;
quit;

title 'CASE g7';
proc causalgraph nosort maxlist=1;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X, X ==> K;
identify X ==> Y | K;
run;
quit;

title 'CASE h1';
proc causalgraph nosort minimal;
model 'M6' X ==> Y, Q ==> X, P ==> X, Z ==> Q P Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE h2';
proc causalgraph minimal;
model 'M6' X ==> Y, Q ==> X, P ==> X, Z ==> Q P Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE h3';
proc causalgraph nosort maxlist=1 minimal;
model 'M6' X ==> Y, Q ==> X, P ==> X, Z ==> Q P Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE h4';
proc causalgraph nosort maxlist=3 minimal;
model 'M6' X ==> Y, Q ==> X, P ==> X, Z ==> Q P Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE h5';
proc causalgraph method=backdoor nosort minimal;
model 'M6' X ==> Y, Q ==> X, P ==> X, Z ==> Q P Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE h6';
proc causalgraph nosort minimal maxsize=2;
model 'M6' X ==> Y, Q ==> X, P ==> X, Z ==> Q P Y, A ==> X B, B ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE h7';
proc causalgraph nosort maxlist=3 minimal;
model 'M6' X ==> Y, Q ==> X, P ==> X, Z ==> Q P Y, A ==> X B, B ==> Y;
identify X ==> Y | Q;
run;
quit;

title 'CASE A';
proc causalgraph nosort;
model "GS"
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
quit;

title 'CASE B';
proc causalgraph method=adjustment nosort maxlist=1;
model "GS"
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
quit;

title 'CASE C';
proc causalgraph nosort maxlist=1;
model "GS"
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
quit;

title 'CASE D';
proc causalgraph nosort maxlist=2;
model "GS"
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
quit;

title 'CASE E';
proc causalgraph method=backdoor nosort maxlist=1;
model "GS"
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
quit;

title 'CASE F';
proc causalgraph nosort minimal;
model "GS"
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
quit;

title 'CASE G';
proc causalgraph maxlist=1;
model "GS"
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
quit;

title 'CASE H';
proc causalgraph method=adjustment nosort maxlist=1;
model "HB"
Age ==> Parity PFAS Education,
Parity ==> PrevBF Duration PFAS,
PrevBF ==> PFAS Duration,
PFAS ==> Duration,
Education ==> Duration HealthBehavior Employment,
HealthBehavior ==> PFAS Duration BMI Alcohol Smoking,
Employment ==> HealthBehavior Duration,
BMI Alcohol Smoking ==> Duration;
identify PFAS ==> Duration;
unmeasured PrevBF;
run;
quit;

title 'CASE H2';
proc causalgraph nosort;
model "HB"
Age ==> Parity PFAS Education,
Parity ==> PrevBF Duration PFAS,
PrevBF ==> PFAS Duration,
PFAS ==> Duration,
Education ==> Duration HealthBehavior Employment,
HealthBehavior ==> PFAS Duration BMI Alcohol Smoking,
Employment ==> HealthBehavior Duration,
BMI Alcohol Smoking ==> Duration;
identify PFAS ==> Duration;
unmeasured PrevBF;
run;
quit;

title 'CASE I';
proc causalgraph nosort;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE I2';
proc causalgraph nosort maxlist=1;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE I3';
proc causalgraph method=backdoor nosort;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE J';
proc causalgraph nosort maxlist=1;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y | W;
run;
quit;

title 'CASE J2';
proc causalgraph nosort;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y | W;
run;
quit;

title 'CASE K';
proc causalgraph nosort maxlist=1 maxsize=1;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE K2';
proc causalgraph nosort maxlist=1 minimal;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE M';
proc causalgraph nosort maxlist=1 method=iv;
model 'V' I ==> X, X ==> Y, U ==> X Y;
identify X ==> Y;
unmeasured U;
run;
quit;

title 'CASE N';
proc causalgraph nosort maxlist=1;
model 'M1' X ==> Y, Z ==> X Y, W ==> Y;
model 'M2' X ==> Y, W ==> X Y, Z ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE O';
proc causalgraph nosort maxlist=1 psummary;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE P';
proc causalgraph nosort maxlist=1 compact;
model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X;
identify X ==> Y;
run;
quit;

title 'CASE Q';
proc causalgraph nosort maxlist=1;
model 'J' X1 ==> Y, X2 ==> Y, Z ==> X1 X2 Y, X1 ==> X2;
identify X1 X2 ==> Y;
run;
quit;

title 'CASE R';
proc causalgraph nosort maxlist=1;
model 'U' X ==> Y, U ==> X Y;
identify X ==> Y;
unmeasured U;
run;
quit;

title 'CASE R2';
proc causalgraph nosort;
model 'U' X ==> Y, U ==> X Y, W ==> Y;
identify X ==> Y;
unmeasured U;
run;
quit;

title 'CASE S';
proc causalgraph nosort maxlist=1;
model 'D' X ==> M, M ==> Y, Z ==> X Y, X ==> D, A ==> Z, A ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE S2';
proc causalgraph nosort;
model 'D' X ==> M, M ==> Y, Z ==> X Y, X ==> D, A ==> Z, A ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE T';
proc causalgraph ;
model 'B' X ==> Y, C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12 C13 C14 C15 C16 C17 C18 C19 C20 C21 C22 C23 C24 C25 ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE T2';
proc causalgraph nosort maxlist=1;
model 'B' X ==> Y, C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12 C13 C14 C15 C16 C17 C18 C19 C20 C21 C22 C23 C24 C25 ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE T3';
proc causalgraph nosort;
model 'B' X ==> Y, C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12 C13 C14 C15 C16 C17 C18 C19 C20 C21 C22 C23 C24 C25 ==> X Y;
identify X ==> Y;
run;
quit;

title 'CASE U2';
proc causalgraph nosort maxlist=1;
model 'B22' X ==> Y, Z ==> X Y, W1 W2 W3 W4 W5 W6 W7 W8 W9 W10 W11 W12 W13 W14 W15 W16 W17 W18 W19 W20 W21 W22 ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE V1';
proc causalgraph nosort maxlist=5;
model 'B12' X ==> Y, Z ==> X Y, W1 W2 W3 W4 W5 W6 W7 W8 W9 W10 W11 W12 ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE V2';
proc causalgraph maxlist=5;
model 'B12' X ==> Y, Z ==> X Y, W1 W2 W3 W4 W5 W6 W7 W8 W9 W10 W11 W12 ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE V3';
proc causalgraph nosort maxlist=5;
model 'B14' X ==> Y, Z ==> X Y, W1 W2 W3 W4 W5 W6 W7 W8 W9 W10 W11 W12 W13 W14 ==> Y;
identify X ==> Y;
run;
quit;

title 'CASE V4';
proc causalgraph maxlist=5;
model 'B14' X ==> Y, Z ==> X Y, W1 W2 W3 W4 W5 W6 W7 W8 W9 W10 W11 W12 W13 W14 ==> Y;
identify X ==> Y;
run;
quit;
