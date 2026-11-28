/* expect-rc: 2
 * STAT-NESTED-002: the variance-component path implemented here is the
 * balanced closed form of the Getting Started default analysis. The same
 * Auto sample data with one observation removed is unbalanced; its
 * estimation (Unbalanced Data, STAT-NESTED-003) is not implemented and must
 * fail visibly with no listing instead of printing balanced-formula numbers.
 */
data auto;
input Make $ Model Score @@;
datalines;
a 1 62 a 2 77 a 3 59 a 1 67 a 2 73 a 3 64 a 1 60 a 2 79 a 3 60
b 1 72 b 2 58 b 3 80 b 1 75 b 2 63 b 3 84 b 1 69 b 2 57 b 3 89
c 1 94 c 2 76 c 3 81 c 1 90 c 2 75 c 3 85 c 1 88 c 2 78 c 3 85
d 1 69 d 2 73 d 3 90 d 1 72 d 2 88 d 3 87 d 1 76 d 2 87 d 3 92
;
proc sort data=auto; by Make Model; run;
data auto; set auto; if _n_ ne 5; run;
proc nested data=auto; class Make Model; var Score; run;
