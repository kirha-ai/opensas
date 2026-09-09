data vs;
  usubjid="S01"; sbp=120.5; run;
proc datasets library=work nolist;
  modify vs;
    attrib sbp format=6.1 label='Systolic BP';
quit;
proc contents data=vs out=meta noprint; run;
proc print data=meta noobs; run;
