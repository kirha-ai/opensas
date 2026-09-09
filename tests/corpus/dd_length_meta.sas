data dm;
  length usubjid $10 sex $1 country $3;
  usubjid="SUBJ-001"; sex="M"; country="USA"; age=45;
run;
proc contents data=dm out=meta(keep=name length) noprint; run;
proc sort data=meta out=metas; by name; run;
proc print data=metas noobs; run;
