/* gfmt_writebatch: YYMON / JULDAY / PDJULIAN / ROMAN / WORDS / DATEAMPM / MMSS /
   B8601DA / B8601DT / B8601TM / NLDATM / NLTIME / NLMNY write formats.
   GAP-fmtwritebatch (doc-finder tick126). Oracle: Language Reference: Concepts pp.146-150,
   sas-functions-ref p.680. d=04JUL2020 (day-of-year 186), t=14:05:06. */
data _null_;
  d = mdy(7,4,2020); t = hms(14,5,6); dt = dhms(d,14,5,6); n = 1234;
  put "YYMON="    d yymon7.;
  put "JULDAY="   d julday3.;
  put "PDJULIAN=" d pdjulian7.;
  put "ROMAN="    n roman8.;
  put "WORDS="    n words.;
  put "DATEAMPM=" dt dateampm23.;
  put "MMSS="     t mmss8.;
  put "B8601DA="  d b8601da10.;
  put "B8601DT="  dt b8601dt.;
  put "B8601TM="  t b8601tm8.;
  put "NLDATM="   dt nldatm18.;
  put "NLTIME="   t nltime8.;
  put "NLMNY="    n nlmny10.;
run;
