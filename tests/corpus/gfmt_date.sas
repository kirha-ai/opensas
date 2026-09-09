/* date_format: DATE / MMDDYY / DDMMYY / YYMMDD write formats. Phase-G. */
data _null_;
  d = mdy(7,4,2020);
  put "DATE="   d date9.;
  put "MMDDYY=" d mmddyy10.;
  put "DDMMYY=" d ddmmyy10.;
  put "YYMMDD=" d yymmdd10.;
run;
