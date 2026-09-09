/* Parse a compound subject ID with SCAN/SUBSTR */
data dm; input RAWID $20.; datalines;
STUDY01-SITE02-003
STUDY01-SITE05-011
;
run;
data parsed;
  set dm;
  length study $7 site $6 subj $3;
  study   = scan(RAWID, 1, "-");
  site    = scan(RAWID, 2, "-");
  subj    = scan(RAWID, 3, "-");
  sitenum = substr(site, 5);
run;
proc print data=parsed; var study site subj sitenum; run;
