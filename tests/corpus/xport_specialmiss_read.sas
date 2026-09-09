/* XPORT READ of a SAS-convention special missing: in the transport format a
   missing numeric is byte0 = '.', '_', or 'A'-'Z' with a zero mantissa
   (TS-140). tests/corpus/includes/xport_specialmiss.xpt is hand-authored to
   that convention (a=.A, b=._, c=plain .) — the reader must surface the
   letters, not collapse to plain missing. Locks the correct read side; the
   WRITE side's collapse is filed in docs/findings/doc-finder-tick220.md. */
libname i xport "tests/corpus/includes/xport_specialmiss.xpt";
data back; set i.d; run;
data _null_; set back;
  put "a=" a " b=" b " c=" c;
run;
