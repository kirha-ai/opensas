/* GAP-gapsexitingone §5d — OPTIONS NOREPLACE is a documented SAS 9.4 system
   option (Language Reference: Concepts p.178 names REPLACE/NOREPLACE) that opensas does not
   implement: valid SAS refused, so D-009 says rc 2 ("file an opensas issue"),
   not 1. The keyword guard matches the option itself — a typo like
   `noreplac` lands on "system option {s} is not recognized" at rc 1 — so the
   refusal is a gap with no typo arm. Pinned in-source (main.zig's §5d test);
   this pins the real process rc through the CLI exit path so the two
   surfaces cannot drift. The PROC PRINT first keeps the golden non-empty
   (the global-statement ERROR errhalt-skips only LATER steps).
   expect-rc: 2 */
data a;
  x = 1;
run;
proc print data=a;
run;
options noreplace;
