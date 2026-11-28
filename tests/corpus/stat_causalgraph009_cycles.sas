/* expect-rc: 1
 * STAT-CAUSALGRAPH-009 (Limitations, p.2329): the models must be DAGs. A
 * model with a directed cycle prints VariableInfo, the summary (and the
 * ConnectedComponents table of a disconnected model) and one DirectedCycles
 * table per cyclic model (case-insensitively alphabetically first node on
 * a cycle, first such successor leading back; mixed-case steps E01-E07),
 * then one error per cyclic model and no
 * adjustment sets. Expected listing: SAS 9.4 reference run of these steps
 * (2026-11-28). Invented graphs.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title 'C01'; proc causalgraph; model 'A' B ==> C ==> A ==> B; identify A ==> C; run;
title 'C02'; proc causalgraph; model 'K' Q ==> P, P ==> Q, R ==> Q; identify R ==> Q; run;
title 'C04'; proc causalgraph; model 'T' M ==> N ==> M, A ==> B ==> A, A ==> M; identify A ==> N; run;
title 'C05'; proc causalgraph; model 'G' X ==> Y; model 'H' X ==> Y ==> Z ==> Y; identify X ==> Y; run;
title 'C06'; proc causalgraph; model 'H1' X ==> Y ==> X; model 'H2' X ==> Z ==> Y ==> Z; identify X ==> Y; run;
title 'C08'; proc causalgraph; model 'N' LongVariableName ==> B ==> LongVariableName; run;
title 'C09'; proc causalgraph; model 'Ch' A ==> B, B ==> C, C ==> D, D ==> C; identify A ==> B; run;
title 'C10'; proc causalgraph; model 'Two' A ==> C ==> A, A ==> B ==> A; identify A ==> B; run;
title 'C11'; proc causalgraph; model 'U' X ==> U ==> Y ==> X; identify X ==> Y; unmeasured U; run;
title 'C12'; proc causalgraph; model 'Rev' Z ==> Y ==> X ==> W ==> Z; identify X ==> W; run;
title 'C13'; proc causalgraph; model 'Long' A ==> B ==> C ==> D ==> E ==> F ==> B; identify A ==> F; run;
title 'C14'; proc causalgraph; model 'Ok' X ==> Y, Z ==> X Y; model 'Cyc' X ==> Y, Y ==> Z ==> X; identify X ==> Y; run;
title 'C15'; proc causalgraph; model 'D1' P <== Q, Q <== R, R <== P, S ==> P; identify S ==> P; run;
title 'C17'; proc causalgraph; model 'Dis' X ==> Y, A ==> B ==> A; identify X ==> Y; run;
title 'E01'; proc causalgraph; model 'M1' a ==> B ==> a, B ==> Y; identify a ==> Y; run;
title 'E02'; proc causalgraph; model 'M2' X ==> b, X ==> C, b ==> X, C ==> X, X ==> Y; identify X ==> Y; run;
title 'E03'; proc causalgraph; model 'M3' z ==> Y, Y ==> Q ==> z, X ==> Y; identify X ==> Y; run;
title 'E04'; proc causalgraph; model 'M4' A ==> B, B ==> E ==> B, A ==> C ==> A, A ==> Y; identify A ==> Y; run;
title 'E05'; proc causalgraph; model 'M5' A ==> B ==> D, A ==> C ==> A, A ==> Y; identify A ==> Y; run;
title 'E06'; proc causalgraph; model 'M6' p ==> Q ==> r ==> p, P2 ==> Q, Q ==> Y; identify P2 ==> Y; run;
title 'E07'; proc causalgraph; model 'M7' A ==> C ==> A, A ==> b ==> A, A ==> Y; identify A ==> Y; run;
