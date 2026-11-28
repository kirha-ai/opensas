/* expect-rc: 1
 * STAT-NESTED-003: Analysis of Covariation (balanced and unbalanced, AOV suppression), CLASS/VAR names of 7-8 characters, BY groups (one WARNING per unbalanced BY group), unsorted CLASS runs, a zero sum of squares printed as 0 (boundary: zero mean squares give 0 correlations), mixed-sign variance components (variance-component correlation 0).
 * Invented data (D-011). The expected listing is a SAS 15.4 reference run of
 * this program (every case logs "WARNING: The design is not balanced--F tests
 * cannot be computed.", hence rc 1 as SAS); the blank line SAS writes before
 * each new page title is dropped (opensas starts pages without it).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data L;
input Longname Factor_B Response Second_V @@;
datalines;
1 1 3 1  1 1 5 2  1 2 4 4  1 2 6 3  1 2 8 7
2 1 7 5  2 1 9 6  2 1 8 8  2 2 2 1
3 1 6 2  3 1 4 5  3 2 5 5  3 2 7 4  3 3 9 9  3 3 6 3
;
title 'R1 eight-char names';
proc nested data=L; class Longname Factor_B; var Response Second_V; run;
data L7; set L; rename Longname=Seven_c Factor_B=Factor7; run;
title 'R1b seven-char names';
proc nested data=L7; class Seven_c Factor7; var Response; run;
data byd;
input G A B y z @@;
datalines;
1 1 1 3 1  1 1 1 5 2  1 1 2 4 4  1 1 2 6 3  1 1 2 8 7  1 2 1 7 5  1 2 1 9 6  1 2 2 2 1  1 2 2 4 2
2 1 1 3 3  2 1 1 5 4  2 2 1 4 1  2 2 1 6 6  2 2 2 8 2  2 2 2 7 5  2 3 1 1 8  2 3 1 5 3
;
title 'R2 BY groups';
proc nested data=byd; by G; class A B; var y z; run;
data auto;
input Make $ Model Score @@;
S2 = mod(Score*7, 11) + Score/2;
datalines;
a 1 62 a 2 77 a 3 59 a 1 67 a 2 73 a 3 64 a 1 60 a 2 79 a 3 60
b 1 72 b 2 58 b 3 80 b 1 75 b 2 63 b 3 84 b 1 69 b 2 57 b 3 89
c 1 94 c 2 76 c 3 81 c 1 90 c 2 75 c 3 85 c 1 88 c 2 78 c 3 85
d 1 69 d 2 73 d 3 90 d 1 72 d 2 88 d 3 87 d 1 76 d 2 87 d 3 92
;
proc sort data=auto; by Make Model; run;
title 'R3 balanced covariation';
proc nested data=auto; class Make Model; var Score S2; run;
data uns;
input A B y @@;
datalines;
1 1 4 1 1 6 1 2 5 1 2 7 1 1 9 1 1 8 2 1 3 2 1 5 2 2 6 2 2 4 2 2 8
;
title 'R5 unsorted runs';
proc nested data=uns; class A B; var y; run;
title 'R6 AOV unbalanced';
proc nested data=L aov; class Longname Factor_B; var Response Second_V; run;
data mix;
input A B y z @@;
datalines;
1 1 5 1 1 1 6 9 1 2 5 2 1 2 6 8 1 2 5 3
2 1 5 7 2 1 6 2 2 2 6 9 2 2 5 1
3 1 6 8 3 1 5 2 3 1 5 9
;
title 'R7 mixed sign components';
proc nested data=mix; class A B; var y z; run;
