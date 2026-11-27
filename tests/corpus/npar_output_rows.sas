/* Independent W/KW output contract. x has2classes with ranks1,2/3,4;
   ylong has3classes with ranks1.5/3.5/5.5. Exact label counts give1/3
   two-sided W, and1/15 KW with1/30 mid-p. The t approximation uses df3;
   T3 lower tail=.5-(atan(u)+u/(1+u²))/pi, u=(1.5/sqrt(5/3))/sqrt(3).
   Every generated column is printed below; typed descriptors/BY union are
   additionally checked in Zig without relying on this listing's formatting. */
ods graphics off;
data sample;
input visit g $ x ylong;
datalines;
1 A 1 1
1 A 2 1
1 B 3 2
1 B 4 2
1 C . 3
1 C . 3
2 A 11 11
2 A 12 11
2 B 13 12
2 B 14 12
2 C . 13
2 C . 13
;
run;
proc npar1way data=sample wilcoxon noprint;
by visit;
class g;
var x ylong;
exact wilcoxon / point midp;
output out=stats wilcoxon;
run;
data _null_;
set stats;
format visit _WIL_ Z_WIL PL_WIL PR_WIL P2_WIL PTL_WIL PTR_WIL PT2_WIL XPL_WIL XPR_WIL XPT_WIL XMP_WIL XP2_WIL _KW_ DF_KW P_KW XP_KW XPT_KW XMP_KW 12.6;
put visit _VAR_ _WIL_ Z_WIL PL_WIL PR_WIL P2_WIL PTL_WIL PTR_WIL PT2_WIL XPL_WIL XPR_WIL XPT_WIL XMP_WIL XP2_WIL _KW_ DF_KW P_KW XP_KW XPT_KW XMP_KW;
run;
