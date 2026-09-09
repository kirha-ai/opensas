data dm;
  length usubjid $4 arm $8;
  usubjid="S01"; arm="Active"; age=45; format age 3.; label age="Age (y)";
run;
proc contents data=dm out=meta noprint; run;
proc sort data=meta out=metas; by varnum; run;
proc print data=metas noobs; run;
