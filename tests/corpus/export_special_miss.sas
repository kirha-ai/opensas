/* NOTE-exportspecialmiss: PROC EXPORT keeps the special-missing letter —
   .A/.Z/._ export as ".A"/".Z"/"._" so "missing because A" survives the file;
   a PLAIN missing still exports empty (BUG-exportmissing). The re-import shows
   the letters in the file (they read back as text — readDelimited has no
   special-missing parse; that read side is deliberately out of scope). */
data d;
  a = .A; z = .Z; u = ._; p = .; n = 5;
run;
proc export data=d outfile="tests/corpus/includes/esm_fixture.csv" dbms=csv replace; run;
proc import datafile="tests/corpus/includes/esm_fixture.csv" out=back dbms=csv replace; run;
proc print data=back noobs; run;
