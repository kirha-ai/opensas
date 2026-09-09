/* ISO 8601 week-based intervals WEEKV/YEARV/QTRV (doc-finder tick139).
   01JAN2021 is Friday, ISO week 53 of ISO-year 2020. */
data _null_;
  length s $12;
  d = mdy(1,1,2021);
  wv = intnx('weekv', d, 0, 'b'); s=put(wv,date9.); put "weekv_begin=" s;
  yv = intnx('yearv', d, 0, 'b'); s=put(yv,date9.); put "yearv_begin=" s;
  qv = intnx('qtrv',  d, 0, 'b'); s=put(qv,date9.); put "qtrv_begin=" s;
  ck = intck('weekv', mdy(1,1,2021), mdy(1,15,2021)); put "weekv_ck=" ck;
run;
