/* BUG-commaxinformat: COMMAX/DOLLARX read the European convention — PERIOD is
   the thousands separator, COMMA the decimal point (`1.234,56` -> 1234.56).
   Was read with the US roles (-> 1.23456) and the INPUT() form returned
   missing. US COMMA/DOLLAR keep comma=grouping, period=decimal. */
data _null_;
  a = input("1.234,56", commax10.2);
  b = input("$1.234,56", dollarx12.2);
  c = input("1,234.56", comma10.2);   /* US roles unchanged */
  d = input("$1,234.56", dollar12.2);
  put a= b= c= d=;
run;
data cx;
  input x commax10.2;
  datalines;
1.234,56
;
run;
proc print data=cx; run;
data dx;
  input y dollarx12.2;
  datalines;
$1.234,56
;
run;
proc print data=dx; run;
