/* BUG-libnamelenloss: the native .sas7bdat write→read round-trip keeps a char
   column's DECLARED length — `length code $8` holding "AB"/"CD" must come back
   Len 8, not the data max 2 (declared width is controlled SDTM metadata; a
   shrunk width silently truncates later-stored longer values). PROC COPY to a
   directory libname writes src.sas7bdat EAGERLY; the second libname's preloaded
   copy comes through the sas7bdat READER (not the in-memory dataset), so both
   sides of the length metadata are exercised.
   Cites docs/findings/qa-findings-tick113.md. */
data src;
  length code $8;
  input code $;
datalines;
AB
CD
;
run;
libname L "tests/corpus/includes/libnamelenloss";
proc copy in=work out=L;
  select src;
run;
libname R "tests/corpus/includes/libnamelenloss";
data back; set R.src; run;
proc contents data=back; run;
data _null_;
  dsid = open("back");
  vl = varlen(dsid, 1);
  put "VARLEN(code)=" vl;
  rc = close(dsid);
run;
