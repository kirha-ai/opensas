data lb;
  usubjid="S01"; aval=5.126; run;
proc datasets library=work nolist;
  modify lb;
    format aval 6.2;
    label aval='Lab Value';
quit;
proc contents data=lb out=meta noprint; run;
proc print data=meta noobs; run;
