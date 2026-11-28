/* expect-rc: 1
 * STAT-CAUSALGRAPH-005: TESTID and METHOD=IV user errors give no listing
 * (message texts of a batched SAS 9.4 reference run, pp.2303, 2319-2321):
 * no direct X -> Y edge under METHOD=IV, an unmeasured TESTID variable
 * (also the UNMEASURED rule of p.2321, formerly a STAT-CAUSALGRAPH-003 gap),
 * TESTID without IDENTIFY, not exactly one IV variable, treatment as a
 * control, conditioning on the treatment, the outcome or an unmeasured
 * variable, duplicate labels, an unmeasured instrument, unknown TESTID
 * options and path types (SAS: ERROR 22-322), several treatments under
 * METHOD=IV (formerly a STAT-CAUSALGRAPH-004 gap), a treatment as the
 * instrument, an outcome as a control, an instrument absent from a model.
 * Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph method=iv; model 'A' Z ==> X ==> M ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; run;
proc causalgraph; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid U; unmeasured U; run;
proc causalgraph; model "T" Z ==> X ==> Y, U ==> X Y; identify X ==> Y; testid U; unmeasured U; run;
proc causalgraph; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; testid U; run;
proc causalgraph method=iv; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid; run;
proc causalgraph method=iv; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid Z W; run;
proc causalgraph; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid U X; run;
proc causalgraph method=iv; model 'TESTID Demo' Z ==> X ==> Y, U => X Y, W => Z U; identify X => Y; testid Z / conditional=(X); run;
proc causalgraph; model 'P' X ==> Y, C ==> X Y; identify X ==> Y; testid 'L' C; testid 'L'; run;
proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U Z; testid Z; run;
proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; testid Z / conditional=Y; run;
proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y, X ==> M; identify X ==> Y; unmeasured U; testid Z / conditional=M; testid Z / conditional=U; run;
proc causalgraph; model 'P' X ==> Y, C ==> X Y; identify X ==> Y; testid C / foo; run;
proc causalgraph; model 'P' X ==> Y, C ==> X Y; identify X ==> Y; testid C / paths=bogus; run;
proc causalgraph method=iv; model 'M' Z ==> X1 ==> Y, X2 ==> Y, U ==> X1 Y; identify X1 X2 ==> Y; unmeasured U; run;
proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; testid X; run;
proc causalgraph; model 'P' X ==> Y, C ==> X Y; identify X ==> Y; testid C Y; run;
proc causalgraph method=iv; model 'A' Z ==> X ==> Y, U ==> X Y; model 'B' X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; testid Z; run;
