/* ORACLE-crossread-half: real SAS rejects packed-only digits under E8601DA and
   E8601DN, while B8601DA remains lenient for both packed and extended dates. */
data _null_;
  eda = input("20180915", e8601da10.);
  edn = input("20180915", e8601dn10.);
  bex = input("2018-09-15", b8601da10.);
  bpk = input("20180915", b8601da8.);
  put "FUNC_EDA=[" eda "] FUNC_EDN=[" edn "] BEXT=[" bex "] BPACK=[" bpk "]";
  if _error_ then put "FUNC_ERR=1";
  else put "FUNC_ERR=0";
run;

data _null_;
  input eda e8601da10.;
  put "STMT_EDA=[" eda "]";
  if _error_ then put "STMT_ERR=1";
  else put "STMT_ERR=0";
datalines;
20180915
;
run;
