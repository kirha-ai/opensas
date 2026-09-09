data raw1; usubjid="S01"; val=1; run;
data raw2; usubjid="S02"; val=2; run;
data scratch; usubjid="S03"; val=3; run;
proc datasets library=work nolist;
  change raw1=dm;
  delete scratch;
quit;
proc print data=dm noobs; run;
