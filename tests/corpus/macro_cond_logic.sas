/* %if / %do %while honor logical and/or and the mnemonic comparison operators
   (eq ne gt ge lt le), matching %eval — regression guard for BUG-macroevalcond. */
%macro band(x);
  data _null_;
  %if &x >= 1 and &x <= 10 %then %do; put "&x in-range"; %end;
  %else %do; put "&x out-of-range"; %end;
  run;
%mend;
%band(5)
%band(20)

%macro flag(v);
  data _null_;
  %if &v eq YES or &v eq Y %then %do; put "&v -> ON"; %end;
  %else %do; put "&v -> off"; %end;
  run;
%mend;
%flag(YES)
%flag(Y)
%flag(no)

/* %do %while over a token list, terminated by a mnemonic ne against empty */
%let cols = AGE SEX RACE;
%macro walk;
  %let i = 1;
  %let c = %scan(&cols, &i);
  %do %while(&c ne );
    data _null_; put "col&i=&c"; run;
    %let i = %eval(&i + 1);
    %let c = %scan(&cols, &i);
  %end;
%mend;
%walk
