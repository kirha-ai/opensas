data d; input x y f; datalines;
1 1 10
1 2 4
2 2 8
2 3 2
3 3 7
;
title "converge=.001 maxiter=200"; ods exclude all; ods output PolychoricCorr=o; proc corr data=d polychoric(converge=.001 maxiter=200); var x y; freq f; run; ods exclude none; proc print data=o; format _numeric_ best32.; run;
title "converge=.0001 maxiter=200"; ods exclude all; ods output PolychoricCorr=o; proc corr data=d polychoric(converge=.0001 maxiter=200); var x y; freq f; run; ods exclude none; proc print data=o; format _numeric_ best32.; run;
title "converge=.00001 maxiter=200"; ods exclude all; ods output PolychoricCorr=o; proc corr data=d polychoric(converge=.00001 maxiter=200); var x y; freq f; run; ods exclude none; proc print data=o; format _numeric_ best32.; run;
title "converge=.000001 maxiter=200"; ods exclude all; ods output PolychoricCorr=o; proc corr data=d polychoric(converge=.000001 maxiter=200); var x y; freq f; run; ods exclude none; proc print data=o; format _numeric_ best32.; run;
title "converge=.0001 maxiter=5"; ods exclude all; ods output PolychoricCorr=o; proc corr data=d polychoric(converge=.0001 maxiter=5); var x y; freq f; run; ods exclude none; proc print data=o; format _numeric_ best32.; run;
title "converge=.0001 maxiter=10"; ods exclude all; ods output PolychoricCorr=o; proc corr data=d polychoric(converge=.0001 maxiter=10); var x y; freq f; run; ods exclude none; proc print data=o; format _numeric_ best32.; run;
title "converge=.0001 maxiter=15"; ods exclude all; ods output PolychoricCorr=o; proc corr data=d polychoric(converge=.0001 maxiter=15); var x y; freq f; run; ods exclude none; proc print data=o; format _numeric_ best32.; run;
