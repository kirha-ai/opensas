/* STAT-CAUSALGRAPH-004: joint causal effects in the IDENTIFY statement
 * (several treatment and/or outcome variables, pp.2302-2303; Identifying
 * Joint Treatment Effects p.2317). Invented graphs. The listing tokens are
 * those of a batched SAS 9.4 reference run of exactly these steps (only
 * page-break blank lines differ); the sets were first derived by hand with
 * the adjustment criterion for sets (PCP = proper causal path nodes,
 * forbidden = De(PCP) + X, d-separation in the proper back-door graph):
 *
 * J1  X1 X2 ==> Y, Z ==> X1 Y: {Z}. Title "Causal Effect of {X1 X2} on Y".
 * J2  sequential X1 ==> L ==> X2 ==> Y, X1 ==> Y, U ==> L Y: PCP = {Y}
 *     (L reaches Y only through X2) so L is allowed; X2 <- L <- U -> Y
 *     needs L or U and L opens X1 -> L <- U -> Y: {U} (minimal), {L,U}.
 * J2U J2 with U unmeasured: no set; the joint NOTE adds "Adjustment sets
 *     might exist for individual treatment effects."
 * J3  W ==> X Z1, Z1 ==> Y1, V ==> Z1 Y2, X ==> Y1 Y2 (W V unmeasured),
 *     X ==> Y1 Y2: Y1 needs Z1, Z1 opens X <- W -> Z1 <- V -> Y2: no set
 *     although each outcome is identified (J3A {Z1},{Y2,Z1}; J3B {} only).
 *     The joint NOTE also appears for one treatment with two outcomes.
 * J4/J5 disconnected joint models: ConnectedComponents only.
 * J6  model B lacks X2: warning, B's sets over X1 alone ({Z}), title still
 *     {X1 X2}; summary Treatments 2 and 1.
 * J7  X ==> Y1 ==> Y2, Z ==> X Y2, X on {Y1 Y2}: {Z}.
 * J8  Getting Started graph, PFAS Parity ==> Duration: PrevBF is a mediator
 *     of Parity and a confounder of PFAS, so no set.
 * J9  the p.2303 example spelling with ranges and a prescribed set.
 * J10 a treatment in no model is ignored with a warning.
 * J5C/J4C identify X2 X1 ==> Y2 Y1 (and the braced, prescribed spelling):
 *     {C,D}, {C,D,E}; titles sort the names: {X1 X2} on {Y1 Y2}.
 * J11 identify X x ==> Y is a single effect (title without braces).
 * J12 {X} ==> (Y): single effect.
 * J13 PSUMMARY with no joint set: only the joint NOTE.
 * J14 a prescribed variable in no model is ignored with a warning.
 * K2  B ==> Q ==> P, A ==> Q, Z ==> B P, identify B A ==> Q P: {Z}, title
 *     {A B} on {P Q} (alphabetical, not model or IDENTIFY order).
 * K3  M2 lacks X2, Y2 and W: three warnings; M1 {W,Z}, M2 {Z}.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'J1';
proc causalgraph;
  model "J1" X1 X2 ==> Y, Z ==> X1 Y;
  identify X1 X2 ==> Y;
run;
title 'J2';
proc causalgraph;
  model "J2" X1 ==> L ==> X2 ==> Y, X1 ==> Y, U ==> L Y;
  identify X1 X2 ==> Y;
run;
title 'J2U';
proc causalgraph;
  model "J2U" X1 ==> L ==> X2 ==> Y, X1 ==> Y, U ==> L Y;
  identify X1 X2 ==> Y;
  unmeasured U;
run;
title 'J3';
proc causalgraph;
  model "J3" W ==> X Z1, Z1 ==> Y1, V ==> Z1 Y2, X ==> Y1 Y2;
  identify X ==> Y1 Y2;
  unmeasured W V;
run;
title 'J3A';
proc causalgraph;
  model "J3A" W ==> X Z1, Z1 ==> Y1, V ==> Z1 Y2, X ==> Y1 Y2;
  identify X ==> Y1;
  unmeasured W V;
run;
title 'J3B';
proc causalgraph;
  model "J3B" W ==> X Z1, Z1 ==> Y1, V ==> Z1 Y2, X ==> Y1 Y2;
  identify X ==> Y2;
  unmeasured W V;
run;
title 'J4';
proc causalgraph;
  model "J4" C ==> X1 Y1, D ==> X2 Y2, X1 ==> Y1, X2 ==> Y2, E ==> Y1;
  identify {X1 X2} ==> {Y1 Y2} | {C};
run;
title 'J5';
proc causalgraph;
  model "J5" C ==> X1 Y1, D ==> X2 Y2, X1 ==> Y1, X2 ==> Y2, E ==> Y1;
  identify X2 X1 ==> Y2 Y1;
run;
title 'J6';
proc causalgraph;
  model "A" X1 X2 ==> Y, Z ==> X1 Y;
  model "B" X1 ==> Y, Z ==> X1 Y;
  identify X1 X2 ==> Y;
run;
title 'J7';
proc causalgraph;
  model "J7" X ==> Y1 ==> Y2, Z ==> X Y2;
  identify X ==> Y1 Y2;
run;
title 'J8';
proc causalgraph;
  model "Timm17TwoLatent"
  Age ==> Parity PFAS Education,
  Parity ==> PrevBF Duration PFAS,
  PrevBF ==> PFAS Duration,
  PFAS ==> Duration,
  Education ==> Duration Employment PFAS BMI Alcohol Smoking,
  Employment ==> Duration PFAS BMI Alcohol Smoking,
  BMI Alcohol Smoking ==> Duration;
  identify PFAS Parity ==> Duration;
  unmeasured Alcohol Smoking;
run;
title 'J9';
proc causalgraph;
  model "J9" x1-x3 ==> y1 y5, c1-c4 z ==> x1 y1, c1 ==> y5;
  identify {x1-x3} ==> {y1 y5} | {c1-c4 z};
run;
title 'J10';
proc causalgraph;
  model "J10" X1 X2 ==> Y, Z ==> X1 Y;
  identify X1 X2 Q ==> Y;
run;
title 'J5C';
proc causalgraph;
  model "J5C" C ==> X1 Y1, D ==> X2 Y2, X1 ==> Y1, X2 ==> Y2, E ==> Y1, X1 ==> Y2;
  identify X2 X1 ==> Y2 Y1;
run;
title 'J4C';
proc causalgraph;
  model "J4C" C ==> X1 Y1, D ==> X2 Y2, X1 ==> Y1, X2 ==> Y2, E ==> Y1, X1 ==> Y2;
  identify {X1 X2} ==> {Y1 Y2} | {C};
run;
title 'J6';
proc causalgraph;
  model "A" X1 X2 ==> Y, Z ==> X1 Y;
  model "B" X1 ==> Y, Z ==> X1 Y;
  identify X1 X2 ==> Y;
run;
title 'J11';
proc causalgraph;
  model "J11" X ==> Y, Z ==> X Y;
  identify X x ==> Y;
run;
title 'J12';
proc causalgraph;
  model "J12" X ==> Y, Z ==> X Y;
  identify {X} ==> (Y);
run;
title 'J13';
proc causalgraph psummary;
  model "J13" X1 ==> L ==> X2 ==> Y, X1 ==> Y, U ==> L Y;
  identify X1 X2 ==> Y;
  unmeasured U;
run;
title 'J14';
proc causalgraph;
  model "J14" X1 X2 ==> Y, Z ==> X1 Y;
  identify X1 X2 ==> Y | Q;
run;
title 'K2';
proc causalgraph;
  model "K2" B ==> Q ==> P, A ==> Q, Z ==> B P;
  identify B A ==> Q P;
run;
title 'K3';
proc causalgraph;
  model "M1" X1 X2 ==> Y1 Y2, Z ==> X1 Y1, W ==> Y2;
  model "M2" X1 ==> Y1, Z ==> X1 Y1;
  identify X1 X2 ==> Y1 Y2 | W;
run;
