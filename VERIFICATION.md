# Verification record

Prepared from GBAura baseline:

`03d7a3f1f8fa577256fd6c5b1b1bb0536e732858`

Pinned mGBA Source Code Form:

`c3c8e5e813f245028de118a56734e1dc0f35ce2a`

Published-file Git blob identities:

- `patches/mgba_mpl_modifications.cmake` — `4b5691cf4074260bcf35e89ca9ea10d49a47c6c2`
- `gbaura-mpl/SaveConverterUtil.java` — `cc437c439fe6cec6c6615d1622d5349ceff40c83`
- `LICENSE` — `14e2f777f6c395e7e04ab4aa306bbcc4b0c1120e`

Those blob identities match the files used by the corresponding GBAura source
baseline.

Automated reproduction was verified by GitHub Actions on 2026-10-07:

- Workflow: `Verify MPL source package`
- Run ID: `37553099651`
- Result: **success**

The verification checked that:

1. the mGBA submodule resolved to the exact pinned commit;
2. the MPL source modification module executed successfully;
3. every file listed in `MODIFIED_FILES.txt` existed in the resulting modified
   Source Code Form;
4. the published MPL license, patch module and `SaveConverterUtil.java` were
   present.

The successful run reported the same expected and actual mGBA commit:

`c3c8e5e813f245028de118a56734e1dc0f35ce2a`
