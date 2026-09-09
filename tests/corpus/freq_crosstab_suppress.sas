/* Two-way crosstab with display suppression: `/ nopercent norow` drops the cell
   Percent and Row Pct lines, leaving Frequency + Col Pct per cell and a
   Frequency-only marginal Total row (FREQ-crosstabpct/displayopts). Same data as
   freq_crosstabpct: colTot N=5 Y=3, grand=8.
     DRUG,N col 2/5=40.00 ; DRUG,Y col 2/3=66.67 ; PLAC,N col 3/5=60.00 ; PLAC,Y col 1/3=33.33 */
data d;
  input trt $ resp $;
  datalines;
DRUG Y
DRUG Y
DRUG N
DRUG N
PLAC Y
PLAC N
PLAC N
PLAC N
;
run;
proc freq data=d;
  tables trt*resp / nopercent norow;
run;
