/* DOLLARw.d informat reads a currency-formatted cost */
data ec;
  input COST dollar12.2;
  datalines;
$1,234.50
$45,000.00
;
run;
proc print data=ec; run;
