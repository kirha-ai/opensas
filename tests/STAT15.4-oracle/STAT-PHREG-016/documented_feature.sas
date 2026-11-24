/* STAT-PHREG-016: PHREG — CONTRAST / ESTIMATE / TEST
 * Source: S154 / Chapter 92 / `CONTRAST Statement` (PDF pp. 7359–7362); S154 / Chapter 92 / `ESTIMATE Statement` (PDF pp. 7362–7364); S154 / Chapter 92 / `TEST Statement` (PDF pp. 7389–7391).
 * Discriminates: Example 92.3: Modeling with Categorical Predictors; explicit statements: CONTRAST, ESTIMATE, TEST
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Myeloma;
input Time VStatus LogBUN HGB Platelet Age LogWBC Frac
LogPBM Protein SCalc;
label Time='Survival Time'
VStatus='0=Alive 1=Dead';
datalines;
1.25 1 2.2175 9.4 1 67 3.6628 1 1.9542 12 10
1.25 1 1.9395 12.0 1 38 3.9868 1 1.9542 20 18
2.00 1 1.5185 9.8 1 81 3.8751 1 2.0000 2 15
2.00 1 1.7482 11.3 0 75 3.8062 1 1.2553 0 12
2.00 1 1.3010 5.1 0 57 3.7243 1 2.0000 3 9
3.00 1 1.5441 6.7 1 46 4.4757 0 1.9345 12 10
5.00 1 2.2355 10.1 1 50 4.9542 1 1.6628 4 9
5.00 1 1.6812 6.5 1 74 3.7324 0 1.7324 5 9
6.00 1 1.3617 9.0 1 77 3.5441 0 1.4624 1 8
6.00 1 2.1139 10.2 0 70 3.5441 1 1.3617 1 8
6.00 1 1.1139 9.7 1 60 3.5185 1 1.3979 0 10
6.00 1 1.4150 10.4 1 67 3.9294 1 1.6902 0 8
7.00 1 1.9777 9.5 1 48 3.3617 1 1.5682 5 10
7.00 1 1.0414 5.1 0 61 3.7324 1 2.0000 1 10
7.00 1 1.1761 11.4 1 53 3.7243 1 1.5185 1 13
9.00 1 1.7243 8.2 1 55 3.7993 1 1.7404 0 12
11.00 1 1.1139 14.0 1 61 3.8808 1 1.2788 0 10
11.00 1 1.2304 12.0 1 43 3.7709 1 1.1761 1 9
11.00 1 1.3010 13.2 1 65 3.7993 1 1.8195 1 10
11.00 1 1.5682 7.5 1 70 3.8865 0 1.6721 0 12
11.00 1 1.0792 9.6 1 51 3.5051 1 1.9031 0 9
13.00 1 0.7782 5.5 0 60 3.5798 1 1.3979 2 10
14.00 1 1.3979 14.6 1 66 3.7243 1 1.2553 2 10
15.00 1 1.6021 10.6 1 70 3.6902 1 1.4314 0 11
16.00 1 1.3424 9.0 1 48 3.9345 1 2.0000 0 10

16.00 1 1.3222 8.8 1 62 3.6990 1 0.6990 17 10
17.00 1 1.2304 10.0 1 53 3.8808 1 1.4472 4 9
17.00 1 1.5911 11.2 1 68 3.4314 0 1.6128 1 10
18.00 1 1.4472 7.5 1 65 3.5682 0 0.9031 7 8
19.00 1 1.0792 14.4 1 51 3.9191 1 2.0000 6 15
19.00 1 1.2553 7.5 0 60 3.7924 1 1.9294 5 9
24.00 1 1.3010 14.6 1 56 4.0899 1 0.4771 0 9
25.00 1 1.0000 12.4 1 67 3.8195 1 1.6435 0 10
26.00 1 1.2304 11.2 1 49 3.6021 1 2.0000 27 11
32.00 1 1.3222 10.6 1 46 3.6990 1 1.6335 1 9
35.00 1 1.1139 7.0 0 48 3.6532 1 1.1761 4 10
37.00 1 1.6021 11.0 1 63 3.9542 0 1.2041 7 9
41.00 1 1.0000 10.2 1 69 3.4771 1 1.4771 6 10
41.00 1 1.1461 5.0 1 70 3.5185 1 1.3424 0 9
51.00 1 1.5682 7.7 0 74 3.4150 1 1.0414 4 13
52.00 1 1.0000 10.1 1 60 3.8573 1 1.6532 4 10
54.00 1 1.2553 9.0 1 49 3.7243 1 1.6990 2 10
58.00 1 1.2041 12.1 1 42 3.6990 1 1.5798 22 10
66.00 1 1.4472 6.6 1 59 3.7853 1 1.8195 0 9
67.00 1 1.3222 12.8 1 52 3.6435 1 1.0414 1 10
88.00 1 1.1761 10.6 1 47 3.5563 0 1.7559 21 9
89.00 1 1.3222 14.0 1 63 3.6532 1 1.6232 1 9
92.00 1 1.4314 11.0 1 58 4.0755 1 1.4150 4 11
4.00 0 1.9542 10.2 1 59 4.0453 0 0.7782 12 10
4.00 0 1.9243 10.0 1 49 3.9590 0 1.6232 0 13
7.00 0 1.1139 12.4 1 48 3.7993 1 1.8573 0 10
7.00 0 1.5315 10.2 1 81 3.5911 0 1.8808 0 11
8.00 0 1.0792 9.9 1 57 3.8325 1 1.6532 0 8
12.00 0 1.1461 11.6 1 46 3.6435 0 1.1461 0 7
11.00 0 1.6128 14.0 1 60 3.7324 1 1.8451 3 9
12.00 0 1.3979 8.8 1 66 3.8388 1 1.3617 0 9
13.00 0 1.6628 4.9 0 71 3.6435 0 1.7924 0 9
16.00 0 1.1461 13.0 1 55 3.8573 0 0.9031 0 9
19.00 0 1.3222 13.0 1 59 3.7709 1 2.0000 1 10
19.00 0 1.3222 10.8 1 69 3.8808 1 1.5185 0 10
28.00 0 1.2304 7.3 1 82 3.7482 1 1.6721 0 9
41.00 0 1.7559 12.8 1 72 3.7243 1 1.4472 1 9
53.00 0 1.1139 12.0 1 66 3.6128 1 2.0000 1 11
57.00 0 1.2553 12.5 1 66 3.9685 0 1.9542 0 11
77.00 0 1.0792 14.0 1 60 3.6812 0 0.9542 0 12
;
run;
proc format; value yesno 0='no' 10='yes'; run;
data VALung;
drop check m;
retain Therapy Cell;
infile cards column=column;
length Check $ 1;
label Time='time to death in days'
Kps='Karnofsky performance scale'
Duration='months from diagnosis to randomization'
Age='age in years'
Prior='prior therapy'
Cell='cell type'
Therapy='type of treatment';
format Prior yesno.;
M=Column;
input Check $ @@;
if M>Column then M=1;
if Check='s'|Check='t' then do;
input @M Therapy $ Cell $;
delete;
end;
else do;
input @M Time Kps Duration Age Prior @@;
Status=(Time>0);
Time=abs(Time);
end;
datalines;
standard squamous
72 60 7 69 0 411 70 5 64 10 228 60 3 38 0 126 60 9 63 10
118 70 11 65 10 10 20 5 49 0 82 40 10 69 10 110 80 29 68 0
314 50 18 43 0 -100 70 6 70 0 42 60 4 81 0 8 40 58 63 10
144 30 4 63 0 -25 80 9 52 10 11 70 11 48 10
standard small
30 60 3 61 0 384 60 9 42 0 4 40 2 35 0 54 80 4 63 10
13 60 4 56 0 -123 40 3 55 0 -97 60 5 67 0 153 60 14 63 10
59 30 2 65 0 117 80 3 46 0 16 30 4 53 10 151 50 12 69 0
22 60 4 68 0 56 80 12 43 10 21 40 2 55 10 18 20 15 42 0
139 80 2 64 0 20 30 5 65 0 31 75 3 65 0 52 70 2 55 0
287 60 25 66 10 18 30 4 60 0 51 60 1 67 0 122 80 28 53 0
27 60 8 62 0 54 70 1 67 0 7 50 7 72 0 63 50 11 48 0
392 40 4 68 0 10 40 23 67 10
standard adeno
8 20 19 61 10 92 70 10 60 0 35 40 6 62 0 117 80 2 38 0
132 80 5 50 0 12 50 4 63 10 162 80 5 64 0 3 30 3 43 0
95 80 4 34 0
standard large
177 50 16 66 10 162 80 5 62 0 216 50 15 52 0 553 70 2 47 0
278 60 12 63 0 12 40 12 68 10 260 80 5 45 0 200 80 12 41 10
156 70 2 66 0 -182 90 2 62 0 143 90 8 60 0 105 80 11 66 0
103 80 5 38 0 250 70 8 53 10 100 60 13 37 10
test squamous
999 90 12 54 10 112 80 6 60 0 -87 80 3 48 0 -231 50 8 52 10
242 50 1 70 0 991 70 7 50 10 111 70 3 62 0 1 20 21 65 10
587 60 3 58 0 389 90 2 62 0 33 30 6 64 0 25 20 36 63 0
357 70 13 58 0 467 90 2 64 0 201 80 28 52 10 1 50 7 35 0
30 70 11 63 0 44 60 13 70 10 283 90 2 51 0 15 50 13 40 10
test small
25 30 2 69 0 -103 70 22 36 10 21 20 4 71 0 13 30 2 62 0
87 60 2 60 0 2 40 36 44 10 20 30 9 54 10 7 20 11 66 0
24 60 8 49 0 99 70 3 72 0 8 80 2 68 0 99 85 4 62 0
61 70 2 71 0 25 70 2 70 0 95 70 1 61 0 80 50 17 71 0
51 30 87 59 10 29 40 8 67 0
test adeno
24 40 2 60 0 18 40 5 69 10 -83 99 3 57 0 31 80 3 39 0
51 60 5 62 0 90 60 22 50 10 52 60 3 43 0 73 60 3 70 0
8 50 5 66 0 36 70 8 61 0 48 10 4 81 0 7 40 4 58 0
140 70 3 63 0 186 90 3 60 0 84 80 4 62 10 19 50 10 42 0
45 40 3 69 0 80 40 4 63 0
test large
52 60 4 45 0 164 70 15 68 10 19 30 4 39 10 53 60 12 66 0
15 30 5 63 0 43 60 11 49 10 340 80 10 64 10 133 75 1 65 0
111 60 5 64 0 231 70 18 67 10 378 80 4 65 0 49 30 3 37 0
;
proc phreg data=VALung;
class Prior(ref='no') Cell(ref='large') Therapy(ref='standard');
model Time*Status(0) = Kps Duration Age Cell Prior|Therapy;
run;
proc phreg data=VALung;
class Prior(ref='no') Cell(ref='large') Therapy(ref='standard');
model Time*Status(0) = Kps Duration Age Cell Prior|Therapy
/ selection=backward slstay=0.1;
run;
proc phreg data=VALung;
class Prior(ref='no') Cell(ref='large') Therapy(ref='standard');
model Time*Status(0) = Kps Cell Prior|Therapy;
hazardratio 'H1' Kps / units=10 cl=both;
hazardratio 'H2' Cell / cl=both;
hazardratio 'H3' Therapy / diff=ref cl=both;
contrast 'C1' Kps 10 / estimate=exp;
contrast 'C2' cell 1 0 0, /* adeno vs large */
cell 1 -1 0, /* adeno vs small */
cell 1 0 -1, /* adeno vs squamous */
cell 0 -1 0, /* large vs small */
cell 0 0 -1, /* large vs Squamous */
cell 0 1 -1 /* small vs squamous */
/ estimate=exp;
contrast 'C3' Prior 0 Therapy 1 Prior *Therapy 0,
Prior 0 Therapy 1 Prior *Therapy 1 / estimate=exp;
run;
data Myeloma2;
set Myeloma;
Contrived= (Time <= 65);
run;
proc phreg data=Myeloma2;
model Time*Vstatus(0)=LOGbun HGB Contrived / itprint;
run;
