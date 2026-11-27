# Release and publishing review rules

Apply these rules to release configuration, `justfile`, and `dev-commands.md` changes.

- Confirm that release tags, collection tags, application versions, and NKP version constraints are consistent.
- Check that bundle creation does not reuse a stale archive; the documented workflow deletes an existing bundle before rebuilding it.
- Check that registry paths and OCI references are explicit and point to the intended catalog.
- Verify that new helper commands are documented consistently in both the `justfile` and `dev-commands.md` when required.
- Check that release changes preserve single-application and full-collection workflows where both are supported.
- Require evidence of validation before publishing or deploying a changed bundle.
- Treat registry authentication, image inclusion, air-gapped bundle behavior, and deployment workspace changes as high-risk.
