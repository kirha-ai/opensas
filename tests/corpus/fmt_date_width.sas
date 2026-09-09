/* BUG-fmtdatewidth: narrow date-format widths drop separators / trailing
   components per the SAS 9.4 width ladder; wide widths unchanged. */
data _null_;
  d = '17mar2013'd;
  put d mmddyy6.;   /* 031713 */
  put d mmddyy8.;   /* 03/17/13 (unchanged) */
  put d date5.;     /* 17MAR */
  put d date7.;     /* 17MAR13 (unchanged) */
  put d ddmmyy6.;   /* 170313 */
  put d yymmdd6.;   /* 130317 */
  put d date9.;     /* 17MAR2013 (unchanged) */
  put d yymmdd10.;  /* 2013-03-17 (unchanged) */
  put d mmddyy4.;   /* 0317 */
  put d yymmdd5.;   /* 13-03 */
  put d date4.;     /* **** (below minimum width) */
run;
