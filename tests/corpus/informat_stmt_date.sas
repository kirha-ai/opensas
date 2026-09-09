/* The INFORMAT statement applies DATE/TIME informats to list INPUT (not just the
   :modifier form) — date9./mmddyy./ddmmyy./yymmdd./time. read to SAS numerics,
   comma. still works. corpus-informatstmtdate. */
data _null_;
  informat a date9. b mmddyy10. c ddmmyy10. d yymmdd10. t time8. n comma8.;
  input a b c d t n;
  put "a=" a " b=" b " c=" c " d=" d " t=" t " n=" n;
  datalines;
15JAN2020 01/15/2020 15/01/2020 2020-01-15 12:00:00 1,234
;
run;
