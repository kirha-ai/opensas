/* QA regression (BUG-datefmtcluster fixed): date WRITE formats render properly,
   not the raw SAS date int. d=21930 = Thursday 16JAN2020. */
data _null_;
  d=21930;
  a=put(d,weekdate.); b=put(d,weekdatx.); c=put(d,worddatx.);
  e=put(d,qtr.); f=put(d,qtrr.); g=put(d,yyq6.); h=put(d,weekday1.);
  i=put(d,month2.); j=put(d,day2.); k=put(d,julian5.); l=put(d,yymmn6.);
  put "weekdate=" a;
  put "weekdatx=" b;
  put "worddatx=" c;
  put "qtr=" e;
  put "qtrr=" f;
  put "yyq=" g;
  put "weekday=" h;
  put "month=" i;
  put "day=" j;
  put "julian=" k;
  put "yymmn=" l;
run;
