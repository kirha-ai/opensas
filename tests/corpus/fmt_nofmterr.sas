/* options nofmterr lets an unknown format fall back silently (BUG-unknownfmtsilent) */
options nofmterr;
data _null_;
  a = put(45.7, undefinedfmt.);
  put "a=[" a "]";
run;
