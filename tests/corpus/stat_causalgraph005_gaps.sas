/* expect-rc: 2
 * STAT-CAUSALGRAPH-005: TESTID / METHOD=IV requests without a SAS reference
 * layout or message fail visibly with no listing (D-009): METHOD=IV with
 * bidirected edges, TESTID with a disconnected model, an instrument absent
 * from one model, a treatment named as the instrument, and PATHS with a
 * METHOD=BACKDOOR set holding a descendant of the treatment. Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph method=iv; model 'A' Z ==> X ==> Y, X <==> Y; identify X ==> Y; run;
proc causalgraph disconnected; model 'A' X ==> Y, C ==> X Y, P ==> Q; identify X ==> Y; testid C; run;
proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y; model 'B' X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; testid Z; run;
proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; testid X; run;
proc causalgraph method=backdoor; model 'P' C ==> X ==> Y, C ==> Y, X ==> D; identify X ==> Y; testid C D / paths; run;
