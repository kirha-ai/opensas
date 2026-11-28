/* STAT-CAUSALGRAPH-002: identification analysis of small invented graphs
 * whose adjustment sets are derived by hand (adjustment criterion,
 * pp.2314-2315 of SAS/STAT 15.4 Chapter 37):
 *
 * G1: Z ==> X, Z ==> Y, X ==> M, M ==> Y, W ==> Y, X ==> D; effect X ==> Y.
 *   Proper causal path X -> M -> Y, so the forbidden set is De({M,Y}) =
 *   {M,Y}; candidates D, W, Z. In the proper back-door graph (X -> M
 *   removed) the only X-Y path is X <- Z -> Y, open unless Z is adjusted;
 *   D (a child of X only) and W (a parent of Y only) are free. Sets:
 *   {Z}, {D,Z}, {W,Z}, {D,W,Z} (size, then alphabetical); only {Z} is
 *   minimal. D is a descendant of X that the adjustment criterion allows.
 *   6 nodes, 6 edges, 6 measured.
 * G2: G1 with Z unmeasured: every valid set needs Z, so no set exists
 *   (NOTE); 5 measured, 1 unmeasured.
 * G3: U ==> C ==> X, U ==> Y, X ==> Y with U unmeasured: X <- C <- U -> Y
 *   is blocked only by C; one set {C}, minimal.
 * G4: G1 with the prescribed variable W (IDENTIFY X ==> Y | W): {W,Z}
 *   minimal among the sets containing W, {D,W,Z} not.
 * G5: G1 with PSUMMARY and MINIMAL: only the AdjustList with {Z}.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'G1';
proc causalgraph;
  model "G1" Z ==> X, Z ==> Y, X ==> M, M ==> Y, W ==> Y, X ==> D;
  identify X ==> Y;
run;
title 'G2';
proc causalgraph;
  model "G2" Z ==> X, Z ==> Y, X ==> M, M ==> Y, W ==> Y, X ==> D;
  identify X ==> Y;
  unmeasured Z;
run;
title 'G3';
proc causalgraph;
  model "G3" U ==> C ==> X, U ==> Y, X ==> Y;
  identify X ==> Y;
  unmeasured U;
run;
title 'G4';
proc causalgraph;
  model "G4" Z ==> X, Z ==> Y, X ==> M, M ==> Y, W ==> Y, X ==> D;
  identify X ==> Y | W;
run;
title 'G5';
proc causalgraph psummary minimal;
  model "G5" Z ==> X, Z ==> Y, X ==> M, M ==> Y, W ==> Y, X ==> D;
  identify X ==> Y;
run;
