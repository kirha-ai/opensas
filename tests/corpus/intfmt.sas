/* QA regression: INTFMT(interval, 'L'|'S') recommended format name, verified
   exact against SAS doc p.1070 examples (YYQC4./YYQC6./MONYY7./WEEKDATX15.). */
data _null_;
  f = intfmt('qtr','s');
  g = intfmt('qtr','l');
  h = intfmt('month','l');
  i = intfmt('week','short');
  put "qtr_s=" f;
  put "qtr_l=" g;
  put "month_l=" h;
  put "week_s=" i;
run;
