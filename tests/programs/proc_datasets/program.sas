/*=============================================================================
* Synthetic data. Fixture for CLIN-datasets: PROC DATASETS core sub-statements.
* APPEND extra onto base (row-matched by name), MODIFY renames a column and sets
* label/format, DELETE drops a scratch member, CHANGE renames the member. The
* renamed+appended member is written out to be diffed. Exercises PROC DATASETS
* APPEND / MODIFY(RENAME,LABEL,FORMAT) / DELETE / CHANGE.
*============================================================================*/
libname source "inputs" access=readonly;
libname target "output";

data base;  set source.base;  run;
data extra; set source.extra; run;
data tmp;   set source.tmp;   run;

proc datasets library=work nolist;
    append base=base data=extra;
    modify base;
        rename x=score;
        label score="Test Score";
        format score 8.2;
    delete tmp;
    change base=combined;
quit;

data target.proc_datasets; set combined; run;
