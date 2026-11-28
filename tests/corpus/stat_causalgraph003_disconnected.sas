/* STAT-CAUSALGRAPH-003: disconnected models (MODEL statement p.2304,
 * DISCONNECTED option p.2299). Invented graphs: VariableInfo, summary and
 * the ConnectedComponents table; components are numbered in the order of
 * their alphabetically first node. Without DISCONNECTED the procedure warns
 * and prints no adjustment sets for any model (also when only the second of
 * two models is disconnected); with DISCONNECTED the sets follow the table
 * and range over the nodes of every component. The last step is disconnected
 * only once its bidirected edges are taken into account; later steps: an
 * unmeasured node (listed among the component nodes), DISCONNECTED with two
 * models, two disconnected models (one table each, no sets). The expected
 * listing is a SAS 9.4 reference run of these steps, the blank line SAS
 * writes before each new page title dropped.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title "E1 order by size?";
proc causalgraph;
  model "E1" X ==> Y, B ==> A, C ==> A;
  identify X ==> Y;
run;
title "E2 tie";
proc causalgraph;
  model "E2" X ==> Y, P ==> Q;
  identify X ==> Y;
run;
title "E3 no identify";
proc causalgraph;
  model "E3" X ==> Y, A ==> B;
run;
title "E4 disconnected option";
proc causalgraph disconnected;
  model "E4" X ==> Y, Z ==> X Y, A ==> B;
  identify X ==> Y;
run;
title "E5 two models one disconnected";
proc causalgraph;
  model "E5a" X ==> Y, Z ==> X Y;
  model "E5b" X ==> Y, A ==> B;
  identify X ==> Y;
run;
title "D3 cov path duplicates and group bidirected";
proc causalgraph;
  model "D3" X ==> Y, A <==> B, B <==> C, A <==> C, <==> {A B C}, {A B} <==> {B C}, <==> {Y Y X};
  identify X ==> Y;
run;
title "F1 disconnected with unmeasured";
proc causalgraph;
  model "F1" X ==> Y, A ==> B, U ==> A;
  identify X ==> Y;
  unmeasured U;
run;
title "F2 disconnected option two models";
proc causalgraph disconnected;
  model "P" X ==> Y, A ==> B;
  model "Q" X ==> Y, Z ==> X Y;
  identify X ==> Y;
run;
title "F3 two disconnected models";
proc causalgraph;
  model "P" X ==> Y, A ==> B;
  model "Q" X ==> Y, C ==> D;
  identify X ==> Y;
run;
