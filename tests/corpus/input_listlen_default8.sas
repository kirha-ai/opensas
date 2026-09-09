/* BUG-inputlistlen: a list-input CHARACTER variable with no declared LENGTH and
   no explicit informat width defaults to SAS's 8-char length. The declared
   ($12) and formatted ($20.) forms keep their own widths. */
data imp;
  input nm $;
  datalines;
Christopher
Bob
Alexandra
;
run;
proc print data=imp; run;

data dcl;
  length nm $12;
  input nm $;
  datalines;
Christopher
;
run;
proc print data=dcl; run;

data fmt;
  input nm $20.;
  datalines;
Christopher
;
run;
proc print data=fmt; run;

data dsd;
  infile datalines dsd;
  input nm $ x;
  datalines;
Christopher,5
;
run;
proc print data=dsd; run;
