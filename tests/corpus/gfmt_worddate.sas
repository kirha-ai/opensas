/* worddate_format: WORDDATE/WEEKDATE/WORDDATX/WEEKDATX/MONYY/MONNAME/DOWNAME/
   YEAR/MONTH/DAY/WEEKDAY textual date write formats. Phase-G. */
data _null_;
  d = mdy(7,4,2020);
  put "WORDDATE=" d worddate.;
  put "WEEKDATE=" d weekdate.;
  put "WORDDATX=" d worddatx.;
  put "WEEKDATX=" d weekdatx.;
  put "MONYY="    d monyy7.;
  put "MONNAME="  d monname.;
  put "DOWNAME="  d downame.;
  put "YEAR="     d year4.;
  put "MONTH="    d month2.;
  put "DAY="      d day2.;
  put "WEEKDAY="  d weekday1.;
run;
