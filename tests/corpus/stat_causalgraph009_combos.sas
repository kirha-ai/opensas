/* expect-rc: 1
 * STAT-CAUSALGRAPH-009 (Limitations, p.2329): directed cycles combined with
 * other requests. Per model in listing order (ORDERMODELS applies), a
 * disconnected model prints its ConnectedComponents page and a cyclic model
 * its DirectedCycles table (on that page, else a new one); NOPRINT and
 * PSUMMARY print nothing; TESTID, METHOD=IV, NOLIST, COMPACT, DISCONNECTED
 * and a missing IDENTIFY change nothing; an outcome missing from a later
 * model is reported instead of the cycle. Expected listing: SAS 9.4
 * reference run of these steps (2026-11-28). Invented graphs.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title 'D01'; proc causalgraph ordermodels; model 'Z' X ==> Y ==> X; model 'A' X ==> Y, Y ==> Z ==> X; identify X ==> Y; run;
title 'D02'; proc causalgraph psummary; model 'P' X ==> Y ==> X; identify X ==> Y; run;
title 'D03'; proc causalgraph psummary nolist; model 'P' X ==> Y ==> X; identify X ==> Y; run;
title 'D04'; proc causalgraph; model 'D' X ==> Y, A ==> B; model 'C' X ==> Y ==> X; identify X ==> Y; run;
title 'D05'; proc causalgraph; model 'C' X ==> Y ==> X; model 'D' X ==> Y, A ==> B; identify X ==> Y; run;
title 'D06'; proc causalgraph; model 'E' X ==> Y, A ==> B ==> A; model 'F' X ==> Y, Z ==> X Y; identify X ==> Y; run;
title 'D07'; proc causalgraph; model 'E' X ==> Y, A ==> B ==> A; model 'G' X ==> Y ==> W ==> X; identify X ==> Y; run;
title 'D08'; proc causalgraph noprint; model 'H1' X ==> Y ==> X; model 'H2' X ==> Z ==> Y ==> Z; identify X ==> Y; run;
title 'D09'; proc causalgraph; model 'T' X ==> Y, Z ==> X Y, Y ==> Z; identify X ==> Y; testid Z; run;
title 'D10'; proc causalgraph method=iv; model 'I' Z ==> X ==> Y ==> Z; identify X ==> Y; run;
title 'D11'; proc causalgraph; model 'C1' X ==> Y ==> X; model 'C2' X ==> Z; identify X ==> Y; run;
title 'D12'; proc causalgraph nolist; model 'NL' X ==> Y ==> X; identify X ==> Y; run;
title 'D13'; proc causalgraph; model 'NI' X ==> Y ==> X, Z ==> X; run;
title 'D14'; proc causalgraph disconnected; model 'DD' X ==> Y, A ==> B ==> A; identify X ==> Y; run;
title 'D15'; proc causalgraph compact; model 'Big' X ==> Y, Z ==> X Y, W ==> Z, Y ==> W; identify X ==> Y; run;
