/* ISS-macroargscan (GH#39+#40): macro-call arg scanner must honor quotes and
   comments. A comma inside a quoted literal must not split the arg (#39), and an
   inline block comment between keyword args must not corrupt keyword detect (#40). */
%macro q(label);
  data _null_;
    x = &label;
    put "x=" x;
  run;
%mend;
%q('Other, specify')

%macro u(a=, b=, c=);
  data _null_;
    a = "&a"; b = "&b"; c = "&c";
    put "A=[" a "] B=[" b "] C=[" c "]";
  run;
%mend;
%u(a=COF1, /* x */ b=COVAL_, /* y */ c=200)
