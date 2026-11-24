/* STAT-BOXPLOT-003: BOXPLOT — Percentile Definitions / Continuous Group Variables / Displaying Blocks of Data
 * Source: S154 / Chapter 32 / `Percentile Definitions` (PDF pp. 1415–1416); S154 / Chapter 32 / `Continuous Group Variables` (PDF pp. 1416–1418); S154 / Chapter 32 / `Displaying Blocks of Data` (PDF pp. 1423–1425).
 * Discriminates: Getting Started: BOXPLOT Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);
filename _grfile temp; goptions device=svg gsfname=_grfile;

data Turbine;
informat Day date7.;
format Day date5.;
label KWatts='Average Power Output';
input Day @;
do i=1 to 10;
input KWatts @;
output;
end;
drop i;
datalines;
05JUL94 3196 3507 4050 3215 3583 3617 3789 3180 3505 3454
05JUL94 3417 3199 3613 3384 3475 3316 3556 3607 3364 3721
06JUL94 3390 3562 3413 3193 3635 3179 3348 3199 3413 3562
06JUL94 3428 3320 3745 3426 3849 3256 3841 3575 3752 3347
07JUL94 3478 3465 3445 3383 3684 3304 3398 3578 3348 3369
07JUL94 3670 3614 3307 3595 3448 3304 3385 3499 3781 3711
08JUL94 3448 3045 3446 3620 3466 3533 3590 3070 3499 3457
08JUL94 3411 3350 3417 3629 3400 3381 3309 3608 3438 3567
11JUL94 3568 2968 3514 3465 3175 3358 3460 3851 3845 2983
11JUL94 3410 3274 3590 3527 3509 3284 3457 3729 3916 3633
12JUL94 3153 3408 3741 3203 3047 3580 3571 3579 3602 3335
12JUL94 3494 3662 3586 3628 3881 3443 3456 3593 3827 3573
13JUL94 3594 3711 3369 3341 3611 3496 3554 3400 3295 3002
13JUL94 3495 3368 3726 3738 3250 3632 3415 3591 3787 3478
14JUL94 3482 3546 3196 3379 3559 3235 3549 3445 3413 3859
14JUL94 3330 3465 3994 3362 3309 3781 3211 3550 3637 3626
15JUL94 3152 3269 3431 3438 3575 3476 3115 3146 3731 3171
15JUL94 3206 3140 3562 3592 3722 3421 3471 3621 3361 3370
18JUL94 3421 3381 4040 3467 3475 3285 3619 3325 3317 3472
18JUL94 3296 3501 3366 3492 3367 3619 3550 3263 3355 3510
;
ods graphics off;
title 'Box Plot for Power Output';
proc boxplot data=Turbine;
plot KWatts*Day;
run;
data Oilsum;
input Day KWattsL KWatts1 KWattsX KWattsM
KWatts3 KWattsH KWattsS KWattsN;
informat Day date7. ;
format Day date5. ;
label Day ='Date of Measurement'
KWattsL='Minimum Power Output'
KWatts1='25th Percentile'
KWattsX='Average Power Output'
KWattsM='Median Power Output'
KWatts3='75th Percentile'
KWattsH='Maximum Power Output'
KWattsS='Standard Deviation of Power Output'
KWattsN='Group Sample Size';
datalines;
05JUL94 3180 3340.0 3487.40 3490.0 3610.0 4050 220.3 20
06JUL94 3179 3333.5 3471.65 3419.5 3605.0 3849 210.4 20
07JUL94 3304 3376.0 3488.30 3456.5 3604.5 3781 147.0 20
08JUL94 3045 3390.5 3434.20 3447.0 3550.0 3629 157.6 20
11JUL94 2968 3321.0 3475.80 3487.0 3611.5 3916 258.9 20
12JUL94 3047 3425.5 3518.10 3576.0 3615.0 3881 211.6 20
13JUL94 3002 3368.5 3492.65 3495.5 3621.5 3787 193.8 20
14JUL94 3196 3346.0 3496.40 3473.5 3592.5 3994 212.0 20
15JUL94 3115 3188.5 3398.50 3426.0 3568.5 3731 199.2 20
18JUL94 3263 3340.0 3456.05 3444.0 3505.5 4040 173.5 20
;
options nogstyle;
title 'Box Plot for Power Output';
proc boxplot history=Oilsum;
plot KWatts*Day / cframe = vligb
cboxes = dagr
cboxfill = ywh;
run;
options gstyle;
goptions reset=symbol;
title 'Schematic Box Plot for Power Output';
ods graphics on;
proc boxplot data=Turbine;
plot KWatts*Day / boxstyle = schematic
outbox = OilSchematic;
run;

/* Numerical companion to the graph: native OUTBOX rows. */
proc print data=OilSchematic noobs; format _numeric_ best16.; run;
