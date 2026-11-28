/* STAT-ANOVA-001 close-out: NAMELEN= effect-name shortening, two CLASS
 * statements, ORDER=FREQ, empty input (NOTE only). Invented data. Every
 * printed token was checked in order against the SAS 9.4 listing of the
 * same steps (ODS Graphics off). */
ods graphics off;
data L;
  input averyveryverylongname_aa $ anotherverylongname_bbb $ y;
  datalines;
a x 1
a y 2
b x 4
b y 7
a x 2
a y 3
b x 5
b y 9
;
title 'Q3 namelen default';
proc anova data=L; class averyveryverylongname_aa anotherverylongname_bbb; model y=averyveryverylongname_aa|anotherverylongname_bbb; run; quit;
title 'Q4 namelen 40';
proc anova data=L namelen=40; class averyveryverylongname_aa anotherverylongname_bbb; model y=averyveryverylongname_aa|anotherverylongname_bbb; run; quit;
data b;
  input u v g y;
  datalines;
1 2 1 1
1 2 2 3
1 1 1 2
1 1 2 6
2 1 1 5
2 1 2 4
2 2 1 7
2 2 2 9
;
title 'Q7 two CLASS statements';
proc anova data=b; class u; class g; model y=g; run; quit;
title 'Q9 order=freq';
data o; input g $ y; datalines;
b 1
a 2
c 3
c 4
c 5
b 6
;
proc anova data=o order=freq; class g; model y=g; run; quit;
title 'Q10 empty';
data e; set o; if y>100; run;
proc anova data=e; class g; model y=g; run; quit;
data m;
  input g anotherveryveryverylongname_bbb y;
  datalines;
1 1 1
1 2 2
2 1 4
2 2 7
1 1 2
1 2 3
2 1 5
2 2 9
;
title 'N1 short first';
proc anova data=m; class g anotherveryveryverylongname_bbb; model y=g|anotherveryveryverylongname_bbb; run; quit;
title 'N2 short second';
proc anova data=m; class g anotherveryveryverylongname_bbb; model y=anotherveryveryverylongname_bbb|g; run; quit;
data m3; set m; abcdefghijkl=g; run;
title 'N3 twelve and long';
proc anova data=m3; class abcdefghijkl anotherveryveryverylongname_bbb; model y=abcdefghijkl|anotherveryveryverylongname_bbb; run; quit;
