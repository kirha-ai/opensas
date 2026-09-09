data lb;
  length usubjid $4 param $6;
  usubjid="S01"; param="ALT"; aval=42; visitnum=1;
run;
proc contents data=lb out=meta(keep=name type length) noprint; run;
proc sort data=meta out=metas; by name; run;
proc print data=metas noobs; run;
