/* GAP-gapsexitingone §5c — the rc-1 half of the hash-method SPLIT, and the
   reason the catch-all could not simply be re-tagged.

   `fnd` is not in the Component Objects reference's dictionary of hash
   language elements, so real SAS 9.4 rejects this program too: the user's
   error, rc 1 ("fix your SAS"). rc_hash_method_gap.sas holds the rc-2 twin
   (`setcur`, a documented method) on the SAME guard — the two fixtures
   together are what make the split real rather than a relabelling.
   expect-rc: 1 */
data _null_;
  length k 8 v 8;
  declare hash h();
  h.defineKey("k");
  h.defineData("v");
  h.defineDone();
  rc = h.fnd();
run;
