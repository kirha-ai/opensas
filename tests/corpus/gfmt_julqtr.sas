/* julqtr_format: JULIAN / YYMMN / QTR / QTRR / YYQ / YYQC write formats. Phase-G. */
data _null_;
  d = mdy(7,4,2020);
  put "JULIAN=" d julian7.;
  put "YYMMN="  d yymmn6.;
  put "QTR="    d qtr1.;
  put "QTRR="   d qtrr3.;
  put "YYQ="    d yyq6.;
  put "YYQC="   d yyqc6.;
run;
