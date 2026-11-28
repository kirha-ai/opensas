/* expect-rc: 2
 * STAT-CAUSALGRAPH-003: valid MODEL forms outside the verified scope fail
 * visibly with no listing: disconnected models with an unmeasured variable,
 * with DISCONNECTED and two models, or two disconnected models (no
 * reference run), ORDERMODELS with two models, and a prescribed adjustment
 * variable that is in only one of two models. Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph; model "U" X ==> Y, A ==> B, U ==> A; identify X ==> Y; unmeasured U; run;
proc causalgraph disconnected; model "P" X ==> Y, A ==> B; model "Q" X ==> Y; identify X ==> Y; run;
proc causalgraph; model "P" X ==> Y, A ==> B; model "Q" X ==> Y, C ==> D; identify X ==> Y; run;
proc causalgraph ordermodels; model "P" X ==> Y, Z ==> X Y; model "Q" X ==> Y; identify X ==> Y; run;
proc causalgraph; model "P" X ==> Y, Z ==> X Y; model "Q" X ==> Y, W ==> X; identify X ==> Y | Z; run;
