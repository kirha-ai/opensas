/* BUG-procimport: the legacy Excel engine shape the study's DV.sas/XA.sas use —
   DBMS=EXCEL with RANGE="Sheet$" — must read the NAMED sheet. RANGE used to be
   ignored (first sheet read instead: silent wrong data) and DBMS=EXCEL rejected. */
proc import out=d datafile="tests/corpus/includes/import_sample.xlsx" dbms=excel replace;
  range="Data$";
  getnames=yes;
run;
proc print data=d noobs; run;
