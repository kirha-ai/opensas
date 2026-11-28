/* STAT-NESTED-004: the Getting Started Auto data (PDF pp. 6967-6969) with
 * the bottom factor repeated (CLASS Make Model Model): the repeated factor
 * has zero degrees of freedom, so Model is tested against it and prints `.`
 * while Make is still tested against Model (F = 569.666667 / 264.861111 =
 * 2.15); every component keeps its Getting Started value (33.867284,
 * 83.425926, 14.583333) and the repeated factor's component is 0.
 * The expected listing is a SAS 15.4 reference run of this program.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data auto;
input Make $ Model Score @@;
datalines;
a 1 62 a 2 77 a 3 59
a 1 67 a 2 73 a 3 64
a 1 60 a 2 79 a 3 60
b 1 72 b 2 58 b 3 80
b 1 75 b 2 63 b 3 84
b 1 69 b 2 57 b 3 89
c 1 94 c 2 76 c 3 81
c 1 90 c 2 75 c 3 85
c 1 88 c 2 78 c 3 85
d 1 69 d 2 73 d 3 90
d 1 72 d 2 88 d 3 87
d 1 76 d 2 87 d 3 92
;
proc sort data=auto; by Make Model; run;
title1 'Reliability of Automobile Models';
proc nested data=auto; class Make Model Model; var Score; run;
