/* GAP-gapsexitingone §5d — the typo arm of the LIBNAME-engine SPLIT:
   `boguseng` is no documented engine, and SAS's own ERROR text for that is
   "The BOGUSENG engine cannot be found." → rc 1 ("fix your SAS"), never the
   gap arm. (SAS/ACCESS engines like ORACLE degrade here too — an unlicensed
   real SAS rejects them the same way, so rc 1 is never a false gap.)
   expect-rc: 1 */
libname t boguseng "nowhere";
