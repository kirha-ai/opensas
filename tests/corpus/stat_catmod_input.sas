/* STAT-CATMOD-001: ORDER=FREQ, formatted classification and response
 * variables, ORDER=FORMATTED, the fractional-frequency Data Summary, WHERE
 * (statement and WHERE= data set option) and the single-character data set
 * name layout. Every listing below is the SAS 9.4 reference output of this
 * same program (batched real-SAS run, 2026-11-28; trailing blanks trimmed).
 * Data: invented. */
options nodate nonumber nocenter linesize=160;
title;
data r;
input g $ y @@;
datalines;
b 2 b 2 a 1 a 1 a 2 c 3 c 3 c 1 b 1 a 3 c 2 b 3 b 1 a 3 c 3
;
title 'Q1 order=freq raw ties';
proc catmod data=r order=freq; response means; model y=g; run; quit;
proc format; value $mg 'a','c'='ac' 'b'='b'; run;
data mg; set r; format g $mg.; run;
title 'Q2 merged population format';
proc catmod data=mg; response means; model y=g; run; quit;
data longname; input g $ y frequency @@; datalines;
a 1 2.5 a 2 3 b 1 4 b 2 1
;
title 'Q3 fractional long names';
proc catmod data=longname; weight frequency; response means; model y=g; run; quit;
data abcdefg; set longname; frequency=frequency*1000; run;
title 'Q4 fractional 7 and big';
proc catmod data=abcdefg; weight frequency; response means; model y=g; run; quit;
data exf; input g $ y w @@; datalines;
a 1 2 a 2 3 b 1 4 b 2 1 b . 2.5
;
title 'Q5 fractional weight only on excluded obs';
proc catmod data=exf; weight w; response means; model y=g; run; quit;
data t;
input g $ y w @@;
datalines;
a 1 3 a 2 4 a 3 3 b 1 6 b 2 1 b 3 8 c 1 5 c 2 5 c 3 0.000001
;
proc format;
value yf 1='one' 2='two' 3='three';
value $gf 'a'='Zed' 'b'='Alpha' 'c'='Mid';
run;
data f; set t; format y yf. g $gf.; run;
title 'P3 formatted internal';
proc catmod data=f; weight w; response means; model y=g; run; quit;
title 'P4 formatted order=formatted';
proc catmod data=f order=formatted; weight w; response means; model y=g; run; quit;
data e; set t; format y 3.; run;
title 'P6 plain numeric format';
proc catmod data=e order=formatted; weight w; response means; model y=g; run; quit;
data fr; set t; if _n_=1 then w=3.5; if _n_=2 then w=4.25; run;
title 'P7 fractional';
proc catmod data=fr; weight w; response means; model y=g; run; quit;
data fr2; set t; w=w*123.37; if _n_=9 then w=.; output; if _n_=9 then do; g=' '; w=7.5; output; end; run;
title 'P8 fractional big and missing';
proc catmod data=fr2; weight w; response means; model y=g; run; quit;
title 'P9 where';
proc catmod data=t; weight w; where w > 1; response means; model y=g; run; quit;
title 'P9 where= data set option';
proc catmod data=t(where=(w > 1)); weight w; response means; model y=g; run; quit;
