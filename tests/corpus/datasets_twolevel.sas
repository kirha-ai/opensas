/* GH#13 ISS-datasetstwolevel: PROC DATASETS CONTENTS with a two-level name
   (libref.member) must resolve the member written earlier under that same
   two-level name. dsQualify must NOT re-qualify TGT.dm13 into TGT.TGT.dm13
   (which missed lib.find and reported "member not found"). One-level DM under
   lib= already worked. Synthesized (no PHI). */
libname TGT ".zig-cache";
data TGT.dm13;
  X=1;
run;
proc datasets lib=TGT nolist;
  contents data=TGT.dm13;
run;
quit;
