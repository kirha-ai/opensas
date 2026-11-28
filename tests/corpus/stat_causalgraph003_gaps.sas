/* expect-rc: 2
 * STAT-CAUSALGRAPH-003: a valid MODEL form outside the verified scope fails
 * visibly with no listing: DISCONNECTED with a disconnected model after the
 * first MODEL statement (the reference run only had the first model
 * disconnected, so the page order is unverified). Invented graph.
 */
options nosyntaxcheck;
proc causalgraph disconnected; model "P" X ==> Y, Z ==> X Y; model "Q" X ==> Y, A ==> B; identify X ==> Y; run;
