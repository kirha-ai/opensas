/* Push a value to the macro symbol table and read it back with SYMGET */
data _null_;
  call symput("arm", "DRUG");
run;
data d;
  length armlbl $8;
  armlbl = symget("arm");
run;
proc print data=d; var armlbl; run;
