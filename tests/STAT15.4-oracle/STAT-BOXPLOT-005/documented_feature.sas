/* STAT-BOXPLOT-005: BOXPLOT — INSET / INSETGROUP / PLOT / Summary Statistics Represented by Box Plots
 * Source: S154 / Chapter 32 / `INSET Statement` (PDF pp. 1378–1381); S154 / Chapter 32 / `INSETGROUP Statement` (PDF pp. 1381–1384); S154 / Chapter 32 / `PLOT Statement` (PDF pp. 1384–1409); S154 / Chapter 32 / `Summary Statistics Represented by Box Plots` (PDF p. 1409).
 * Discriminates: Example 32.1: Displaying Summary Statistics in a Box Plot; explicit statements: INSET, INSETGROUP, PLOT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
ods trace on;


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

run;

ods graphics off;
title 'Box Plot for Power Output';
proc boxplot data=Turbine;
plot KWatts*Day;
inset min mean max stddev /
header = 'Overall Statistics'
pos = tm;
insetgroup min max /
header = 'Extremes by Day';
run;

ods trace off; ods graphics off;
