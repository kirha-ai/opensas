/* INPUT @n column pointer (fixed columns) + single trailing-@ line hold across
   two INPUT statements in one iteration (PG-atptr). */
data fixed;
  input @3 name $4. @8 age 2.;
  put "name=" name "| age=" age;
datalines;
XXann  30
XXcate 25
;
run;

data hold;
  input kind $ @;
  if kind = 'A' then input v1 v2;
  else input v3;
  put "kind=" kind "| v1=" v1 "| v2=" v2 "| v3=" v3;
datalines;
A 10 20
B 99
;
run;
