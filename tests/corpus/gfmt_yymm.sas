/* date_format: YYMMw. / MMYYw. write formats (GAP-fmtyymm). 01MAR2020. */
data _null_;
  d = mdy(3,1,2020);
  put "YYMM7=" d yymm7.;
  put "YYMM5=" d yymm5.;
  put "MMYY7=" d mmyy7.;
  put "MMYY5=" d mmyy5.;
run;
