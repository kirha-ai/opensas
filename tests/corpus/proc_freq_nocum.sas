data have;
  input color $;
  datalines;
red
red
red
blue
;
run;

proc freq data=have;
  tables color / nocum;
run;
