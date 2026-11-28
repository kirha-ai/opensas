/* STAT-CAUSALGRAPH-003: MODEL bidirected edges and covariance paths
 * (SAS/STAT 15.4 MODEL statement pp.2304-2306, Arrow or Edge Specification
 * p.2316). Invented small graphs: a bidirected arrow inside a directed path,
 * covariance paths `<==> {...}` with [], () and {} groups, repeated and
 * reversed bidirected edges (ignored), a directed and a bidirected edge on
 * the same pair, a one-variable covariance path (discarded track), a
 * variance specification X <==> X (ignored), a model connected only through
 * a bidirected edge, a bidirected-only model and bidirected edges with an
 * UNMEASURED variable. Adjustment sets treat u <==> v as a latent common
 * parent (p.2306). Hand check: C1 {Z} blocks X<->Z->Y and X<-Z->Y; C2/C7
 * X<->Y cannot be blocked; C6 M is a collider; C8 W is a collider on
 * X<->W<->Y. The expected listing is a SAS 9.4 reference run of these steps;
 * the blank line SAS writes before each new page title is dropped.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title "C1 bidirected confounding of X and Z";
proc causalgraph;
  model "C1" Z ==> X ==> Y, Z ==> Y, X <==> Z;
  identify X ==> Y;
run;
title "C2 nonidentified X<->Y";
proc causalgraph;
  model "C2" Z ==> X ==> Y, Z ==> Y, X <==> Y;
  identify X ==> Y;
run;
title "C3 covariance path three vars, brackets";
proc causalgraph;
  model "C3" [A B] ==> X ==> Y, <==> (A B Y), A ==> Y;
  identify X ==> Y;
run;
title "C4 Example2 chain, duplicates";
proc causalgraph;
  model "C4" X1 ==> X2 ==> X3 <== X4 <==> X5, X5 <==> X4, <==> {X4 X5}, X4 <-> X5, X5 ==> X3;
  identify X2 ==> X3;
run;
title "C5 bidirected and directed same pair, no identify";
proc causalgraph;
  model "C5" A ==> B, A <==> B, B <=> C;
run;
title "C6 M-bias with bidirected";
proc causalgraph;
  model "C6" X ==> Y, X <==> M, M <==> Y;
  identify X ==> Y;
run;
title "C7 bidirected vs latent expansion, unmeasured";
proc causalgraph;
  model "C7" X ==> M ==> Y, X <==> Y;
  identify X ==> Y;
run;
title "C8 front door style, M <-> Y";
proc causalgraph;
  model "C8" W ==> X ==> Y, W ==> Y, W <==> Y, X <==> W;
  identify X ==> Y;
run;
title "C9 cov path one var";
proc causalgraph;
  model "C9" X ==> Y, <==> {X};
  identify X ==> Y;
run;
title "C10 self bidirected";
proc causalgraph;
  model "C10" X ==> Y, X <==> X;
  identify X ==> Y;
run;
title "C11 connected only by bidirected";
proc causalgraph;
  model "C11" X ==> Y, A ==> B, Y <==> A;
  identify X ==> Y;
run;
title "C12 bidirected only model";
proc causalgraph;
  model "C12" <==> {X Y Z};
  identify X ==> Y;
run;
title "C14 unmeasured with bidirected";
proc causalgraph;
  model "C14" Z ==> X ==> Y, U ==> Z, U ==> Y, X <==> U;
  identify X ==> Y;
  unmeasured U;
run;
