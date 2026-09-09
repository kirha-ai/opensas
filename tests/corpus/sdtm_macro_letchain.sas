/* Build an identifier from chained %LET / &var references */
%let study = ABC;
%let siteid = 01;
%let prefix = &study-&siteid;
data d;
  length id $12;
  id = "&prefix-001";
run;
proc print data=d; var id; run;
