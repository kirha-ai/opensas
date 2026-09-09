/* Parameterized derivation macro applied twice (change from baseline) */
%macro chg(var, base);
  &var.chg = &var - &base;
%mend;
data lb;
  input USUBJID $ ALT baseALT AST baseAST;
  datalines;
01-001 45 40 30 25
01-002 30 35 50 40
;
run;
data d;
  set lb;
  %chg(ALT, baseALT)
  %chg(AST, baseAST)
run;
proc print data=d; var USUBJID ALTchg ASTchg; run;
