/* Public S154 Example79.7 data, numeric UNITS and profile-likelihood CIs.
   This regression requests CLODDS=PL, UNITS age=10, and ID. Its complete
   expected listing comes from the corresponding SAS reference output objects;
   no OpenSAS output was used to generate the expected contract. */
ods graphics off;
data Data1;
input disease n age id $;
datalines;
0 14 25 a
0 20 35 b
0 19 45 c
7 18 55 d
6 12 65 e
17 17 75 f
;
proc logistic data=Data1 plots=none;
model disease/n=age / clodds=pl;
units age=10;
id id;
run;
