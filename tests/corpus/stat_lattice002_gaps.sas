/* expect-rc: 2
 * STAT-LATTICE-002: valid PROC LATTICE designs outside the implemented
 * lattices fail visibly with no listing: a simple rectangular lattice (k = 3,
 * 12 treatments, Overview p.5511; invented data) with strong block effects
 * (Eb > Ee: rectangular recovery not verified), a 4x5 grid that is no
 * lattice, a partially balanced
 * square lattice repeated through Rep, and a partially balanced analysis
 * with a value SAS prints in E notation (2E-6: Displayed Output,
 * STAT-LATTICE-003). Published Getting Started sample data otherwise.
 */
options nosyntaxcheck;
data Pigs;
input Group Block Treatment Weight @@;
datalines;
1 1 1 2.20 1 1 2 1.84 1 1 3 2.18 1 2 4 2.05 1 2 5 0.85
1 2 6 1.86 1 3 7 0.73 1 3 8 1.60 1 3 9 1.76
2 1 1 1.19 2 1 4 1.20 2 1 7 1.15 2 2 2 2.26 2 2 5 1.07
2 2 8 1.45 2 3 3 2.12 2 3 6 2.03 2 3 9 1.63
3 1 1 1.81 3 1 5 1.16 3 1 9 1.11 3 2 2 1.76 3 2 6 2.16
3 2 7 1.80 3 3 3 1.71 3 3 4 1.57 3 3 8 1.13
4 1 1 1.77 4 1 6 1.57 4 1 8 1.43 4 2 2 1.50 4 2 4 1.60
4 2 9 1.42 4 3 3 2.04 4 3 5 0.93 4 3 7 1.78
;
data Rect;
input Group Block Treatment Y @@;
datalines;
1 1 1 10.2 1 1 2 11.5 1 1 3 9.8 1 2 4 12.1 1 2 5 13.0 1 2 6 11.7
1 3 7 8.9 1 3 8 10.4 1 3 9 9.5 1 4 10 12.8 1 4 11 11.1 1 4 12 13.6
2 1 4 11.4 2 1 7 9.9 2 1 10 12.2 2 2 1 10.9 2 2 8 9.7 2 2 11 12.5
2 3 2 12.0 2 3 5 12.4 2 3 12 14.1 2 4 3 9.1 2 4 6 10.8 2 4 9 10.3
;
data Rect2; set Rect; Y = Y + 3*Block*(Group = 1); run;
proc lattice data=Rect2; run;
data grid; do Group = 1 to 2; do Block = 1 to 4; do u = 1 to 5; Treatment = (Block-1)*5 + u; Y = Treatment + Group; output; end; end; end; run;
proc lattice data=grid; var Y; run;
data pr; set Pigs; if Group <= 2; Rep = 1; output; Rep = 2; Weight = Weight + 0.1; output; run;
proc lattice data=pr; var Weight; run;
data small; set Pigs; if group in (2,4); if group=4 then group=1; W10=Weight/10; run;
proc lattice data=small; var W10; run;
