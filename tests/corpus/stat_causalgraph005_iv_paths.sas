/* STAT-CAUSALGRAPH-005: TESTID PATHS= (proper-path enumeration with
 * causal/blocked flags and the biasing-path and over-control footnotes),
 * METHOD=IV searches and tests, COMPACT and PSUMMARY with TESTID. Invented
 * graphs; listing tokens equal a batched SAS 9.4 reference run of exactly
 * these steps (1661 tokens). Hand checks: T01 nothing adjusted, both forks
 * open (biasing); T04 K is a collider descending from X (over-control
 * footnote, X ==> K <== Y opened), X <=> Y is never blocked; T05 C blocks
 * X <== C <== U ==> Y and X <== C ==> Y; T16-T18 instrument Z needs W
 * (Z <- W -> U -> Y); the reported conditioning set follows the SAS
 * search order (A1 kept, ZZ not).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
title 'T01'; proc causalgraph; model 'P' A ==> X, B ==> X, X ==> Y, A ==> Y, B ==> Y, X ==> M2, X ==> M1, M1 ==> Y, M2 ==> Y; identify X ==> Y; testid / paths; run;
title 'T02'; proc causalgraph; model 'P' X ==> Y, B ==> X, A ==> X, B ==> Y, A ==> Y, M ==> Y, X ==> M; identify X ==> Y; testid A / paths; run;
title 'T03'; proc causalgraph; model 'P' X ==> Y, B ==> X, A ==> X, B ==> Y, A ==> Y; model 'Q' X ==> Y, C ==> X Y; identify X ==> Y; testid A / paths; testid / paths=(noncausal nonblocked); run;
title 'T04'; proc causalgraph; model 'P' X ==> Y, X ==> K <== Y, X <==> Y, C ==> X Y; identify X ==> Y; testid C K / paths; run;
title 'T05'; proc causalgraph; model 'P' X ==> Y, C ==> X Y, U ==> C Y; identify X ==> Y; unmeasured U; testid C / paths; run;
title 'T06'; proc causalgraph; model 'P' X ==> Y, C ==> X Y; identify X ==> Y; testid 'test1' C; testid C; testid 'Test2' ; testid C; run;
title 'T11'; proc causalgraph method=iv compact; model 'A' Z ==> X ==> Y, U ==> X Y, C ==> Y; identify X ==> Y | C; unmeasured U; testid Z; testid 'w' Z / conditional=C; run;
title 'T12'; proc causalgraph compact; model 'A' Z ==> X ==> Y, U ==> X Y, C ==> Y; identify X ==> Y; testid; testid U; run;
title 'T13'; proc causalgraph method=iv list; model 'A' Z ==> X ==> Y, U ==> X Y, C ==> Y; identify X ==> Y; unmeasured U; testid Z; run;
title 'T14'; proc causalgraph psummary; model 'P' X ==> Y, C ==> X Y; identify X ==> Y; testid C / paths; run;
title 'T16'; proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y, W ==> Z U, Q ==> W; identify X ==> Y; unmeasured U; run;
title 'T17'; proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y, W ==> Z, W ==> U, A1 ==> Y, B1 ==> Y; identify X ==> Y; unmeasured U; run;
title 'T18'; proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y, W ==> Z, W ==> U, A1 ==> Y, ZZ ==> Y; identify X ==> Y; unmeasured U; run;
title 'T19'; proc causalgraph method=backdoor; model 'P' C ==> X ==> M ==> Y, C ==> Y, X ==> D, X ==> Y, E ==> Y; identify X ==> Y; testid C / paths; run;
title 'T20'; proc causalgraph; model 'P' X ==> Y, C ==> X Y; identify X ==> Y; testid C / paths=(causal); testid C / paths=all; testid C / paths=(blocked noncausal); run;
