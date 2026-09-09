/* BUG-importdelimread (doc-finder tick223): a DSD quoted free-text field
   containing a line break (clinical AE verbatim) is ONE record — columns to
   its right stay aligned/typed — and CSV GETNAMES header text is mangled per
   VALIDVARNAME=V7 and deduped like the XLSX path (GH#62):
   "First Name"→First_Name, "2nd"→_2nd, duplicate age,age→age,age0. */
proc import out=t datafile="tests/corpus/includes/import_newline_hdr.csv" dbms=csv replace;
  getnames=yes;
run;
proc contents data=t out=c(keep=name varnum) noprint; run;
proc sort data=c; by varnum; run;
data _null_; set c; put "NAME=[" name "]"; run;
data _null_; set t; put "ROW=[" subjid "][" First_Name "] age=" age " age0=" age0; run;
