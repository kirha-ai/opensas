/* BUG-setwhererename: a where= that references the RENAMED (new) name must filter
   on it (SAS renames before the WHERE), not drop every row. */
data a;
  length g $2;
  do i = 1 to 4;
    x = i;
    g = cats("G", i);
    output;
  end;
run;
/* numeric: where on the NEW name y — keep y>=3 (2 rows) */
data bnum; set a(rename=(x=y) where=(y>=3)); run;
proc print data=bnum noobs; run;
/* char: where on the NEW name grp — drop G2 (3 rows) */
data bchar; set a(keep=g rename=(g=grp) where=(grp ne "G2")); run;
proc print data=bchar noobs; run;
/* control: where on the ORIGINAL name still works */
data bold; set a(keep=x rename=(x=y) where=(x>=3)); run;
proc print data=bold noobs; run;
