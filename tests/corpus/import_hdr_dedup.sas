/* PERF-importhdrquad: GETNAMES header dedup policy pinned byte-identically
   across the hash-set refactor — duplicates, case variants (x/X, age/Age/AGE0),
   pre-suffixed decoys (x1 collides with the renamed X1), mangled dup (x 1),
   and >32-byte headers colliding after the 32-byte truncation. */
proc import out=t datafile="tests/corpus/includes/import_hdr_dedup.csv" dbms=csv replace;
  getnames=yes;
run;
proc contents data=t out=c(keep=name varnum) noprint; run;
proc sort data=c; by varnum; run;
data _null_; set c; put "NAME=[" name "]"; run;
data _null_; set t; put "ROW=" x ":" x0 ":" X1 ":" x10 ":" x_1 ":" age ":" Age0 ":" AGE00 ":" age1; run;
