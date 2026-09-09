/* audit-tick: macro_fn — one probe per member of the production, routed
   through a DATA-step PUT so the resolved text lands on stdout (%put writes
   to the log stream, which the corpus does not diff). */
%let a = hello world foo;
data _null_;
  put "%substr(&a,1,5)";
  put "%qsubstr(&a,1,5)";
  put "%scan(&a,2)";
  put "%qscan(&a,-1)";
  put "%upcase(&a)";
  put "%qupcase(&a)";
  put "%lowcase(ABC Def)";
  put "%index(&a,world)";
  put "%length(&a)";
  put "%eval(3+4)";
  put "%sysevalf(1/3)";
  put "%str(a;b)";
  put "%nrstr(&a)";
  put "%quote(&a)";
  put "%bquote(&a)";
  put "%nrbquote(&a)";
  put "%superq(a)";
  put "%unquote(&a)";
  put "%sysfunc(int(3.7))";
  put "%qsysfunc(upcase(ab))";
  put "%symexist(a) %sysmacexist(nomacro)";
run;
%global gg; %let gg=1;
data _null_;
  put "%symglobl(gg)";
run;
