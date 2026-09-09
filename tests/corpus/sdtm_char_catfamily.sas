/* Build ids and labels with the CAT family (CATX/CATS/CATT) */
data dm; input site $ subj $ arm $; datalines;
01 001 DRUG
02 011 PLACEBO
;
run;
data lbl;
  set dm;
  length id $8 desc $30;
  id   = catx("-", site, subj);
  desc = catx(" ", id, "on", arm);
run;
proc print data=lbl; var id desc; run;
