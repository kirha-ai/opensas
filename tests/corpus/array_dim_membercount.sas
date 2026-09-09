/* BUG-arraydimmembercount: an ARRAY whose explicit DIMENSION disagrees with
   the explicit member count is a SAS 9.4 ERROR ("The number of variables ...
   does not correspond to the number of elements ..."), not a silent override
   by the member count. The ERROR goes to stderr (asserted via captured
   diagnostics in parser.zig's test); stdout pins that the legal forms still
   run and the bad step halts the whole job (syntax-check mode, BUG-errhalt).
   expect-rc: 1 */

data _null_;
  array ok{3} x y z (10 20 30);  /* dim == member count → fine */
  array st{*} a b c (1 2 3);     /* {*} takes the member count → fine */
  array gen{5};                  /* no members → gen1-gen5, legal */
  gen4 = 99;
  put ok{2};
  put st{3};
  put gen4;
run;

data _null_;
  array big{5} p q r;  /* dim 5 vs 3 members → ERROR, the step stops HERE */
  put 'unreached';     /* never reached */
run;

data _null_;
  array small{2} p q r;  /* dim 2 vs 3 members — also an ERROR, but the job is
                            already in syntax-check mode, so this step is skipped */
  put 'skipped';
run;
