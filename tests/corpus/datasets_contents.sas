/* GH#8 ISS-datasetscontents: CONTENTS inside PROC DATASETS (no NOPRINT) prints
   the same listing standalone PROC CONTENTS renders, instead of hard-erroring.
   Repro from the issue. Synthesized (no PHI). */
data W;
  X=1;
run;
proc datasets lib=work nolist;
  contents data=W;
run;
quit;
