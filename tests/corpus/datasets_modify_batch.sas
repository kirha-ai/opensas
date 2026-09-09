/* BUG-datasetsrenamecollide + BUG-datasetsfmtmulti (PROC DATASETS MODIFY, SAS 9.4).
   (2) `format a b dollar8.2;` applies the ONE trailing spec to BOTH a and b
       (the old parser stored garbage "b8.2" on a and left b untouched); a
       positive RENAME to a free name (score) also works. CONTENTS pins the
       Format column on both a and b, and the renamed var.
   (1) RENAME to an EXISTING name fails loud. It runs LAST: after a step ERROR
       later steps are skipped (BUG-errhalt), so stdout pins the pre-ERROR state;
       proc.zig's unit test pins the captured ERROR + no duplicate column.
   expect-rc: 1 */
data m;
  a = 1; b = 2; c = 3;
run;
proc datasets library=work nolist;
  modify m;
  rename a=score;
  format score b dollar8.2;
quit;
proc contents data=m; run;

proc datasets library=work nolist;
  modify m;
  rename b=score;
quit;
proc print data=m noobs; run;
