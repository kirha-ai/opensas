/* GH#68 ISS-exportcsvmissing: PROC EXPORT dbms=csv must write a numeric missing
   as an EMPTY field (1,,3), not a literal "." (1,.,3) which a strict CSV reader
   reads as data. Read the RAW exported file back (PROC IMPORT would round-trip
   "." to missing and hide the bug — that's why the in-isolation unit test passed
   while the real path stayed broken). Row 2 must be 1,,3. (no PHI) */
data t;
  a=1; b=.; c=3; output;
run;
proc export data=t outfile="tests/corpus/includes/ecm_fixture.csv" dbms=csv replace; run;
data check;
  infile "tests/corpus/includes/ecm_fixture.csv" firstobs=2 truncover;
  length line $32;
  input line $;
run;
proc print data=check noobs; run;
