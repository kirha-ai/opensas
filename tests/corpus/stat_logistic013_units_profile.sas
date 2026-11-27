/* STAT-LOGISTIC-013 supported numeric/profile path, public S154 Example79.7.
   This is a new regression, not a replacement for the full original (which
   additionally requests unimplemented ROC/GOF/RSQUARE/CLPARM/EFFECTPLOT).
   Expected complete listing comes from the SAS reference objects requested
   here; no OpenSAS output was used to generate the expected contract. */
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
