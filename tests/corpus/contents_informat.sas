/* NOTE-contentsinformat: PROC CONTENTS shows an Informat column in the attribute
   table (blank when a var carries no informat) and OUT= carries INFORMAT (name),
   INFORML (width), INFORMD (decimals). x has an assigned informat; y has none. */
data d;
  informat x comma8.;
  x = 1234;
  y = 5;
run;
proc contents data=d out=meta; run;
proc print data=meta noobs; var name informat informl informd; run;
