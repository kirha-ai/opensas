/* FEAT-freq-stratified: independent SAS evidence /tmp/opensas-stat-batch2/FEAT-freq-stratified/examples.sas; displayed numeric tolerance .00005, I2 percent .005. */
options nosyntaxcheck; ods graphics off;
data pain;
input Dose Adverse $ Count @@;
datalines;
0 No 26 0 Yes 6
1 No 26 1 Yes 7
2 No 23 2 Yes 9
3 No 18 3 Yes 14
4 No 9 4 Yes 23
;
run;
proc freq data=pain; tables Adverse*Dose / trend; weight Count; run;
data Hypnosis;
length Emotion $ 10;
input Subject Emotion $ SkinResponse @@;
datalines;
1 fear 23.1 1 joy 22.7 1 sadness 22.5 1 calmness 22.6
2 fear 57.6 2 joy 53.2 2 sadness 53.7 2 calmness 53.1
3 fear 10.5 3 joy 9.7 3 sadness 10.8 3 calmness 8.3
4 fear 23.6 4 joy 19.6 4 sadness 21.1 4 calmness 21.6
5 fear 11.9 5 joy 13.8 5 sadness 13.7 5 calmness 13.3
6 fear 54.6 6 joy 47.1 6 sadness 39.2 6 calmness 37.0
7 fear 21.0 7 joy 13.6 7 sadness 13.7 7 calmness 14.8
8 fear 20.3 8 joy 23.6 8 sadness 16.3 8 calmness 14.8
;
run;
proc freq data=Hypnosis; tables Subject*Emotion*SkinResponse / cmh2 scores=rank noprint; run;
