/* STAT-CAUSALGRAPH-005: TESTID (pp.2319-2321) with METHOD=ADJUSTMENT,
 * BACKDOOR and IV, the CONDITIONAL= and PATHS= options, METHOD=IV LIST
 * (InstrumentList) and METHOD=BACKDOOR LIST. Invented graphs (S01-S05 are
 * the two TESTID Demo programs of p.2319; S10 is the Example 37.5 graph).
 * The listing tokens equal those of a batched SAS 9.4 reference run of
 * exactly these steps (2329 tokens, 0 differing). Hand checks:
 * S01 {U} blocks X <- U -> Y: valid, minimal; {U W} valid, not minimal.
 * S02 BACKDOOR: {} leaves X <- U -> Y open; {Z} and {W} do not block it.
 * S03 Z is no unconditional instrument (Z <- W -> U -> Y open, U latent);
 * S05 given W it is (W blocks that path; X is an unconditioned collider).
 * S06 {C} blocks the fork; {C D} is valid for ADJUSTMENT (D descends from X
 * off the causal paths) but S07 not for BACKDOOR (D is a descendant of X).
 * S09 prescribed C joins every tested set; M is on the causal path in P,
 * absent from Q (valid there, never minimal). S15 model B has Z -> Y.
 * Auto labels skip explicit ones (S02: Test2 Test1 Test3); labels are
 * case-sensitive (S25). Warnings: CONDITIONAL= ignored (S20), PATHS ignored
 * with IV (S21), unknown TESTID variable dropped (S24).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
title 'S01'; proc causalgraph method=adjustment; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid U; testid U W; run;
title 'S02'; proc causalgraph method=backdoor; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid; testid 'Test1' Z; testid W; testid 'Lab two' U W Z; run;
title 'S03'; proc causalgraph method=iv; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid Z; unmeasured U; run;
title 'S04'; proc causalgraph method=iv; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; unmeasured U; run;
title 'S05'; proc causalgraph method=iv; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid Z / conditional=W; testid W; testid W / conditional=(Z); testid 'none' Z / conditional={}; unmeasured U; run;
title 'S06'; proc causalgraph; model 'P' C ==> X ==> M ==> Y, C ==> Y, X ==> D, X ==> Y; identify X ==> Y; testid C / paths; testid / paths=(causal blocked); testid C D / paths=nonblocked; testid 'nc' / paths=noncausal; testid 'bl' C / paths=blocked; run;
title 'S07'; proc causalgraph method=backdoor; model 'P' C ==> X ==> M ==> Y, C ==> Y, X ==> D, X ==> Y; identify X ==> Y; testid C D; testid C; run;
title 'S08'; proc causalgraph method=backdoor; model 'P' C ==> X ==> M ==> Y, C ==> Y, X ==> D, X ==> Y; identify X ==> Y; run;
title 'S09'; proc causalgraph method=adjustment list; model 'P' C ==> X ==> M ==> Y, C ==> Y, X ==> D, X ==> Y; model 'Q' C ==> X ==> Y; identify X ==> Y | C; testid D; testid M; run;
title 'S10'; proc causalgraph method=iv; model "H" Age ==> Parity PFAS Education, Parity ==> PrevBF Duration PFAS, PrevBF ==> PFAS Duration, PFAS ==> Duration, Education ==> Duration HealthBehavior Employment, HealthBehavior ==> PFAS Duration BMI Alcohol Smoking, Employment ==> HealthBehavior Duration, Smoking Alcohol BMI ==> Duration; identify PFAS ==> Duration; unmeasured PrevBF HealthBehavior; run;
title 'S11'; proc causalgraph method=iv; model "H" Age ==> Parity PFAS Education, Parity ==> PrevBF Duration PFAS, PrevBF ==> PFAS Duration, PFAS ==> Duration, Education ==> Duration HealthBehavior Employment, HealthBehavior ==> PFAS Duration BMI Alcohol Smoking, Employment ==> HealthBehavior Duration, BMI Alcohol Smoking Zed ==> Duration; identify PFAS ==> Duration; unmeasured PrevBF HealthBehavior; testid Age; testid Education; testid Parity / conditional=Age; testid Age / conditional=(Education Parity Smoking); run;
title 'S12'; proc causalgraph method=iv; model 'A' Z1 ==> X ==> Y, Z2 ==> X, U ==> X Y, C ==> Z2 Y, Z3 ==> C X; identify X ==> Y; unmeasured U; testid Z2 / conditional=C; run;
title 'S13'; proc causalgraph method=iv; model 'A' X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; run;
title 'S15'; proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y; model 'B' Z ==> X ==> Y, U ==> X Y, Z ==> Y; identify X ==> Y; unmeasured U; testid Z; run;
title 'S16'; proc causalgraph method=iv nolist; model 'A' Z ==> X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; run;
title 'S17'; proc causalgraph list; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid U; run;
title 'S20'; proc causalgraph; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid U / conditional=W; run;
title 'S21'; proc causalgraph method=iv; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid Z / paths; run;
title 'S24'; proc causalgraph; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid Q; run;
title 'S25'; proc causalgraph; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid 'a' U; testid 'A' W; run;
title 'S26'; proc causalgraph; model 'J' X1 ==> Y1 Y2, X2 ==> Y1, C ==> X1 X2 Y1 Y2; identify X1 X2 ==> Y1 Y2; testid C / paths; testid; run;
title 'S27'; proc causalgraph method=backdoor; model 'J' X1 ==> Y1 Y2, X2 ==> Y1, C ==> X1 X2 Y1 Y2; identify X1 X2 ==> Y1 Y2; testid C; run;
title 'S30'; proc causalgraph compact method=iv; model 'A' Z1 ==> X ==> Y, Z2 ==> X, U ==> X Y, C ==> Z2 Y, Z3 ==> C X, E ==> Y; identify X ==> Y; unmeasured U; testid Z2 / conditional=C; run;
title 'S31'; proc causalgraph method=iv; model 'A' Z1 ==> X ==> Y, Z2 ==> X, U ==> X Y, C ==> Z2 Y, Z3 ==> C X, E ==> Y; identify X ==> Y; unmeasured U; run;
title 'S32'; proc causalgraph noprint; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid U; run;
title 'S33'; proc causalgraph psummary; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid U; run;
