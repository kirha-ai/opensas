/* GAP-freqlow-tick276 (doc-finder tick276, F5+F6): PROC FREQ statement surface.
   F6: the PROC FREQ statement option loop now names every token — implemented
   (DATA= / ORDER= / NOPRINT / NLEVELS), legitimately inert pagination/display
   (COMPRESS / PAGE / FORMCHAR=), anything else a loud "option X is not
   supported" (the loud half is pinned by the GAP-freqlow-tick276 test in
   src/proc.zig — a green corpus run cannot contain an ERROR). This fixture is
   the POSITIVE control: every option below must keep parsing and rendering.
   F5: an n-way stratum whose obs ALL have zero weight has no observations —
   SAS prints NO table for it (was: a phantom empty grid "Total 0 / 100.00" a
   reader cannot tell from a real result). `weight w / zeros` re-includes it. */
data d;
  input x;
  datalines;
2
1
2
;
run;
/* implemented: ORDER=FREQ + NLEVELS; inert: COMPRESS PAGE FORMCHAR= */
proc freq data=d compress page formchar='|----|+|---' nlevels order=freq;
  tables x;
run;
/* implemented: NOPRINT suppresses the listing; OUT= still builds */
proc freq data=d noprint;
  tables x / out=xcounts;
run;
proc print data=xcounts;
run;
/* F5: zero-weight stratum h=A prints no table; h=B renders normally */
data w;
  input h $ g $ s $ wt;
  datalines;
A X Y 0
B X Y 5
;
run;
proc freq data=w;
  tables h*g*s;
  weight wt;
run;
/* `weight wt / zeros` re-includes the zero-weight stratum (SAS) */
proc freq data=w;
  tables h*g*s;
  weight wt / zeros;
run;
