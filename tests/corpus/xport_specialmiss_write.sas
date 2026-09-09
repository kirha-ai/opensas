/* BUG-xportwritefidelity F1: XPORT WRITE keeps special missings — a .A/.Z/._
   numeric must ride the file as its TS-140 letter byte (byte0 + zero
   mantissa), not collapse to plain '.'. Write d → xport_specialmiss_write.xpt,
   read it back fresh through a second libname, print. The READ side is locked
   by xport_specialmiss_read; this locks the write→read round trip. */
data d;
  input a b c e;
datalines;
.A .Z ._ 42
;
run;
libname o xport "tests/corpus/includes/xport_specialmiss_write.xpt";
proc copy in=work out=o;
  select d;
run;
libname r xport "tests/corpus/includes/xport_specialmiss_write.xpt";
data back; set r.d; run;
data _null_; set back;
  put "a=" a " b=" b " c=" c " e=" e;
run;
