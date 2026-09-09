/* AUDIT-errhaltclass: `infile "<no such file>"` HALTS the step instead of
   reporting "Physical file does not exist" and reading an EMPTY source.

   Three error arms live in readInfileLines and only ONE of them continued:
   StreamTooLong and ReadFailed already returned error.ExecError, the OPEN
   failure did not — and its own doc comment already claimed the open error was
   "a HARD SAS error … never a silent 0-obs step". Two shapes of real damage,
   both probed on a clean-rebuilt binary:
     (a) `data out; set src; infile 'nope'; input v $; run;` wrote EVERY driver
         row with v MISSING — a fabricated value in a written data set;
     (b) `data sc.keeper; infile 'nope'; input i; run;` REPLACED a live 3-obs
         permanent member with an EMPTY one, at exit 1, readable at exit 0.
   (b) is the inverse of Example Code 8.6's "WARNING: Data set WORK.TEST was not
   replaced because this step was stopped" (Language Reference: Concepts printed p.174-175): data loss
   where the volume promises preservation. The four sibling "File {s} does not
   exist" sites (SET/MERGE sources) have always halted.

   Failing step LAST (BUG-errhalt errhalt-skips later steps). The captured
   diagnostic and the zero-row output are pinned in exec.zig (D-003).
   expect-rc: 1 */
data src;
  input id;
  datalines;
1
2
;
run;

/* Control 1: an INFILE that EXISTS still reads (the halt is open-failure only). */
data _null_;
  infile 'tests/corpus/includes/si_n7.txt';
  input z;
  put 'control z=' z;
run;

/* Control 2: the SET-driven shape that produced the fabricated missings, with a
   real file — every row keeps its read value. */
data mixed;
  set src;
  infile 'tests/corpus/includes/si_n7.txt';
  input z;
run;
data _null_; set mixed; put 'mixed id=' id ' z=' z; run;

/* FAILING STEP, LAST: nothing below the INFILE runs — no INPUT, no PUT, no row. */
data out_never;
  set src;
  infile 'tests/corpus/includes/no_such_file_audit_errhaltclass.dat';
  input v $;
  put 'infile step still ran, v=' v;
run;
