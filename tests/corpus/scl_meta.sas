/* SCL metadata: VARLABEL returns the label (blank if none), VARLEN the declared
   LENGTH, NOBS the row count. Regression guard for BUG-sclmeta. */
data d;
  length name $10;
  input name $ age;
  label age="Age Years";
  datalines;
Alice 30
Bob 25
;
run;
data _null_;
  dsid = open("d");
  la = varlabel(dsid, 2);
  ln = varlabel(dsid, 1);
  wl = varlen(dsid, 1);
  no = nobs(dsid);
  put "label_age=[" la "]";
  put "label_name=[" ln "]";
  put "len_name=" wl;
  put "nobs=" no;
  rc = close(dsid);
run;
