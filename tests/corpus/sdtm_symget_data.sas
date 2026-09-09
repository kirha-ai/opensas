/* Read a macro-symbol value inside a DATA step with SYMGET */
data _null_;
  call symput("study", "PROTO-01");
  call symput("site", "SITE-A");
run;
data d;
  length study $10 site $10;
  study = symget("study");
  site  = symget("site");
run;
proc print data=d; var study site; run;
