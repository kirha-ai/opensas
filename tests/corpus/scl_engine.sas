/* QA regression (E-scl, BUG-sclbind fixed): SCL dataset-access engine end-to-end.
   Covers the 14 value-verified functions: OPEN CLOSE EXIST FETCH FETCHOBS
   GETVARN GETVARC VARNUM CUROBS ATTRN ATTRC VARNAME VARTYPE VARFMT. */
data emp;
  length name $ 10;
  format salary dollar8.;
  input name $ age salary;
  datalines;
Alice 30 50000
Bob 25 45000
Carol 40 60000
;
run;
data _null_;
  ex = exist("emp"); exn = exist("nope");
  d  = open("emp");
  opengt = (d > 0);
  an = attrn(d, "NOBS"); av = attrn(d, "NVARS"); ac = attrc(d, "MEMNAME");
  vn = varnum(d, "age"); nm = varname(d, 1);
  t1 = vartype(d, 1); t2 = vartype(d, 2); fm = varfmt(d, 3);
  rc1 = fetch(d); co = curobs(d); gn = getvarn(d, 2); gc = getvarc(d, 1);
  rc3 = fetchobs(d, 3); gc3 = getvarc(d, 1); gn3 = getvarn(d, 3);
  rcc = close(d);
  put "exist=" ex exn;
  put "open_gt0=" opengt;
  put "attrn=" an av;
  put "attrc=" ac;
  put "varnum=" vn;
  put "varname=" nm;
  put "vartype=" t1 t2;
  put "varfmt=" fm;
  put "fetch_curobs=" rc1 co;
  put "getvar=" gn gc;
  put "fetchobs=" rc3 gc3 gn3;
  put "close=" rcc;
run;
