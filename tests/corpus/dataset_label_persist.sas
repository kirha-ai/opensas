/* F8: the DATASET label persists through a libname round-trip. Before the
   fix `modify d (label=…)` set Dataset.label in memory but NO persistence
   path consumed it — the sas7bdat writer emits no label subheader and the
   .labels sidecar iterated only columns, so a fresh session could never
   recover the label (SDTM domain descriptions ride on it into define.xml).
   The sidecar now carries the dataset label as a reserved `*`-named record
   alongside the column entries. PROC COPY writes eagerly, so the reload
   through libname r comes from DISK (sas7bdat + d.labels), not the
   in-memory set. Cites docs/findings/doc-finder-tick220.md F8. */
libname o "tests/corpus/includes/dslabel";
data o.d; x=1; run;
proc datasets library=o nolist;
  modify d (label='Round Trip DS');
quit;
libname o2 "tests/corpus/includes/dslabel";
proc copy in=o out=o2;
  select d;
run;
libname r "tests/corpus/includes/dslabel";
proc contents data=r.d; run;
