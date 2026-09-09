/* tick225 doc-finder: LOCK PROC EXPORT dbms=csv DSD quoting on WRITE (verified
   correct). A char value containing the delimiter is wrapped in quotes; an
   embedded double-quote is doubled. Read the RAW exported file back (not a
   round-trip PROC IMPORT, which would hide a write bug). Row 2 must be exactly
   "a,b","x""y",5 . (no PHI) */
data t;
  length name $20 note $20;
  name="a,b"; note='x"y'; n=5; output;
run;
proc export data=t outfile="tests/corpus/includes/edq_fixture.csv" dbms=csv replace; run;
data check;
  infile "tests/corpus/includes/edq_fixture.csv" firstobs=2 truncover;
  length line $40;
  input line $char40.;
run;
proc print data=check noobs; run;
