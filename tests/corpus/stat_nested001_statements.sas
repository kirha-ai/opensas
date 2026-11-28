/* expect-rc: 1
 * STAT-NESTED-001: statement rules on invented data (D-011). A BY group
 * whose observations all have a missing VAR value, and a data set with no
 * usable observation, are skipped with "WARNING: All observations contain
 * missing data." (hence rc 1, as SAS); several CLASS or VAR statements
 * concatenate; a VAR variable may repeat (AOV lists it twice); LABEL and
 * ATTRIB LABEL=/FORMAT= leave the listing unchanged, and a LABEL for a
 * variable not in the data set is a WARNING; unquoted LABEL text and ATTRIB
 * LENGTH=/INFORMAT= are accepted; TRUNCATE on a later CLASS statement
 * applies to every CLASS variable (values that differ only after character
 * 16 form one level). The expected listing is a SAS
 * 15.4 reference run of this program; the blank line SAS writes before each
 * new page title is dropped (opensas starts pages without it).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data d; input g a b y z @@; datalines;
1 1 1 3 1 1 1 1 5 2 1 1 2 4 4 1 1 2 8 3 1 2 1 6 5 1 2 1 7 7 1 2 2 2 6 1 2 2 4 9
2 1 1 . 1 2 1 1 . 2 2 1 2 . 4 2 1 2 . 3 2 2 1 . 5 2 2 1 . 7 2 2 2 . 6 2 2 2 . 9
3 1 1 9 1 3 1 1 5 0 3 1 2 6 4 3 1 2 6 2 3 2 1 1 5 3 2 1 3 3 3 2 2 7 6 3 2 2 5 1
;
title 'S1 BY group g=2 all missing';
proc nested data=d; by g; class a b; var y; run;
title 'S2 no usable observation';
proc nested data=d(where=(g=2)); class a b; var y; run;
title 'S3 two CLASS and two VAR statements with AOV';
proc nested data=d(where=(g=3)) aov; class a; class b; var y; var z; run;
title 'S4 repeated VAR variable with AOV';
proc nested data=d(where=(g=1)) aov; class a b; var y y; run;
title 'S5 LABEL and ATTRIB';
proc nested data=d(where=(g=3)); class a b; var z; label z='Zed' q='none'; attrib a label='A' format=8.2 b label='B'; run;
data w; length a $20; input a $ b y @@; datalines;
abcdefghijklmnopA 1 3 abcdefghijklmnopB 1 5 abcdefghijklmnopA 2 4 abcdefghijklmnopB 2 8
zbcdefghijklmnopA 1 6 zbcdefghijklmnopB 1 7 zbcdefghijklmnopA 2 2 zbcdefghijklmnopB 2 4
;
title 'S6 TRUNCATE on the second CLASS statement, unquoted LABEL, ATTRIB';
proc nested data=w; class a; class b / truncate; var y; label y=Yield of plot b=Bee; attrib y length=8 informat=best12. q label='x'; run;
