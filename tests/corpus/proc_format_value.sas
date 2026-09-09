proc format;
  value sexf 1="Male" 2="Female" other="Unknown";
  value agegrp low-17="Pediatric" 18-64="Adult" 65-high="Senior";
  value $ynf "Y"="Yes" "N"="No";
run;

data dm;
  input id sex age comp $;
  slab = put(sex, sexf.);
  agrp = put(age, agegrp.);
  clab = put(comp, $ynf.);
  format sex sexf. age agegrp. comp $ynf.;
  datalines;
1 1 8 Y
2 2 45 N
3 9 70 Y
;
run;

data _null_;
  set dm;
  put "id=" id " slab=" slab " agrp=" agrp " clab=" clab;
run;

proc print data=dm; run;
