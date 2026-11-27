/* Independent raw-value axes: tiny positive units must not become zero labels;
   opposite finite endpoints have an overflowing difference but finite normalized
   coordinates. ODS selects graphs so this fixture tests graphical presentation. */
ods graphics on;
data tiny;
input g $ x;
datalines;
A 1e-9
B 2e-9
A 4e-9
B 6e-9
;
run;
ods select EDFPlot;
proc npar1way data=tiny edf plots(only)=edfplot; class g; var x; run;
data wide;
input g $ x;
datalines;
A -1e308
B -5e307
A 5e307
B 1e308
;
run;
ods select EDFPlot;
proc npar1way data=wide edf; class g; var x; run;
ods graphics off;
