/* BUG-macropctmask: %-escaped specials fold to literals inside quoting fns
   (%str(50%%) is 50%, %str(a%&b) is a&b, %str(a%(b) masks the paren), and a
   folded %/& is masked so it never re-fires as a macro trigger. Synthetic.
   BUG-macropctmask. */
%let pct = %str(50%%);
data _null_; put "STRPCT=[&pct]"; run;
%let amp = %str(a%&b);
data _null_; put "STRAMP=[&amp]"; run;
%let lpar = %str(a%(b);
data _null_; put "STRLPAREN=[&lpar]"; run;
%let ci = %str(95%% CI);
data _null_; put "STRCI=[&ci]"; run;
%let nrp = %nrstr(50%%);
data _null_; put "NRPCT=[&nrp]"; run;
