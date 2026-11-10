/* FEAT-freq-tests: real-SAS evidence docs/findings/freq-tests/included-missing-scores.{txt,log}. */
options nodate nonumber;
ods graphics off;
data scoreprobe;
input x y w;
datalines;
. 10 24
. 20 10
. 30 6
2 10 8
2 20 30
2 30 12
5 10 6
5 20 16
5 30 48
;
run;
title 'TABLE scores with numeric missing';
proc freq data=scoreprobe;
weight w;
tables x*y / missing scores=table chisq measures scorout;
test pcorr scorr gamma;
run;
title 'RANK scores with numeric missing';
proc freq data=scoreprobe;
weight w;
tables x*y / missing scores=rank chisq measures scorout;
test pcorr scorr gamma;
run;
