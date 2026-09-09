/* GH#22 ISS-dkrocondwarn: a KEEP statement naming a never-created var (zzz) is
   a DKROCOND=WARN case in SAS 9.4 — WARN (to stderr), keep only the vars that
   exist (x), drop the rest (y), ignore zzz, and KEEP RUNNING. The following
   step must still run (no syntax-check poison), so w2 and its output appear. */
data w;
  x = 1;
  y = 2;
run;

data w2;
  set w;
  keep x zzz;   /* zzz never referenced -> WARNING, not ERROR; x survives */
run;

data _null_;
  set w2;
  put "w2 produced: x=" x;
run;
