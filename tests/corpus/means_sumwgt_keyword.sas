/* GAP-sumwgtkeyword: SUMWGT is a DOCUMENTED statistic-keyword and was decoded by
   nothing. Base SAS 9.4 Procedures Guide, PROC MEANS statement, printed p.1491
   lists it under "Descriptive statistic keywords"; Table 2.1 printed p.70 scopes it
   to "MEANS or SUMMARY, REPORT, SQL, TABULATE, UNIVARIATE"; and "Keywords and
   Formulas" printed p.2745 gives the value — "SUMWGT is the sum of the weights, W,
   computed as Σwᵢ". Three surfaces were broken in three DIFFERENT ways, all through
   the one shared decoder (statFromKw), which is why one entry fixes all three.

   ARM 1 — the MEANS listing. Previously warned "statistic-keyword sumwgt is not
   recognized and is ignored" (a false claim about a real keyword) and silently
   dropped the column. UNWEIGHTED it must equal N: Statistical Procedures p.410,
   "If there is no WEIGHT variable, the sum of the weights is n" — so 3.

   ARM 2 — the same weighted, w={3,1,1}. Sum of Weights = Σwᵢ = 5, and Sum = Σwᵢxᵢ =
   10*3+20+30 = 80, so the two columns are visibly different quantities and a
   regression that aliased sumwgt onto sum or onto N would show here. Mean = 80/5 =
   16, not the unweighted 20. (Same arithmetic as univ_weight, deliberately.)

   ARM 3 — MEANS `OUTPUT OUT= sumwgt=`. This one did NOT warn; it failed loud, and
   with a MISLEADING message — "OUTPUT statistic-keyword sw is not recognized" named
   the user's chosen variable name rather than the keyword, because the parser lost
   sync once sumwgt failed to decode. _FREQ_ (3, the observation count) and sw (5,
   Σwᵢ) are different numbers here on purpose: they are different statistics.

   ARM 4 — AUTONAME, giving x_SumWgt. The rule is only "the combination of the
   analysis variable name and the statistic-keyword" (Procedures Guide p.1506); no
   volume prints a worked AUTONAME data set, so the suffix CASE follows the house
   convention of its neighbours (StdDev/NMiss/QRange) and is not doc-quoted.

   ARM 5 — the reason this ticket mattered. UNIVARIATE `OUTPUT OUT= sumwgt=` also
   failed loud, which meant the n==0 behaviour settled in NOTE-univallmiss
   (0dfce82e) was UNOBSERVABLE outside the Moments listing. Group a is all-missing:
   sw is 0 while sum/uss/css are missing — the exact split of Procedures Guide p.72
   and p.2749 ("SUM, MEAN, MAX, MIN, RANGE, USS, and CSS require at least one
   nonmissing observation", SUMWGT in neither list) now pinned through a data set a
   downstream step can read, not just through printed text. */
data a; input x w @@; datalines;
10 3 20 1 30 1
;
run;
proc means data=a n sum sumwgt mean;
  var x;
run;
proc means data=a n sum sumwgt mean;
  var x;
  weight w;
run;
proc means data=a noprint;
  var x;
  weight w;
  output out=o n=n sum=s sumwgt=sw mean=m;
run;
proc print data=o; run;
proc means data=a noprint;
  var x;
  weight w;
  output out=o2 sumwgt= / autoname;
run;
proc print data=o2; run;
data bymiss; input g $ x @@; datalines;
b 1 b 2 a . a .
;
run;
proc sort data=bymiss; by g; run;
proc univariate data=bymiss noprint;
  by g;
  var x;
  output out=o3 n=n sum=sum sumwgt=sw uss=uss css=css mean=m;
run;
proc print data=o3; run;
