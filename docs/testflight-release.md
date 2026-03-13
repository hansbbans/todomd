# TestFlight Release Workflow

This repository now includes a manual GitHub Actions workflow at `.github/workflows/testflight-release.yml`.

## What it does

- Runs only when you trigger it with `workflow_dispatch`
- Checks out the branch, tag, or commit you choose
- Regenerates `TodoMD.xcodeproj` with XcodeGen
- Runs `swift test`
- Archives a signed iOS release build
- Uploads the archive directly to TestFlight

Normal development stays on `main`. Nothing is uploaded to TestFlight automatically on merge.

## Project identifiers

These values must match across XcodeGen, entitlements, Apple Developer, and App Store Connect:

- iOS app bundle ID: `com.hans.todomd`
- Share extension bundle ID: `com.hans.todomd.share`
- Widget bundle ID: `com.hans.todomd.widgets`
- Shared app group: `group.com.hans.todomd`

Only the main iOS app needs an App Store Connect app record. All three iOS targets still need explicit App IDs and App Store Connect provisioning profiles in the Apple Developer portal.

## Apple-side setup

### 1. Confirm the app record and App IDs

- In App Store Connect, create or confirm the iOS app record for `com.hans.todomd`.
- In Certificates, Identifiers & Profiles, create or confirm explicit App IDs for:
  - `com.hans.todomd`
  - `com.hans.todomd.share`
  - `com.hans.todomd.widgets`

### 2. Enable the shared app group on all three App IDs

- Enable the `App Groups` capability for each App ID.
- Assign `group.com.hans.todomd` to all three targets.
- If you change capabilities after profiles already exist, regenerate the provisioning profiles. Profiles must be recreated after App ID capability changes.

### 3. Create a local Apple Distribution certificate

The GitHub workflow imports a password-protected `.p12`, so use a local Apple Distribution certificate rather than a cloud-managed-only setup.

1. On a Mac, create a certificate signing request in Keychain Access.
2. In Certificates, Identifiers & Profiles, create an `Apple Distribution` certificate.
3. Download and install the certificate into your login keychain.
4. In Keychain Access, export the certificate and private key as a password-protected `.p12`.

### 4. Create an App Store Connect API key

1. In App Store Connect, request API access if the account has not enabled it yet.
2. Generate a team API key.
3. Download the `.p8` file immediately. Apple only lets you download it once.
4. Record the key ID and issuer ID.

### 5. Create App Store Connect provisioning profiles

Create one App Store Connect provisioning profile per iOS bundle ID, all tied to the same Apple Distribution certificate:

- `com.hans.todomd`
- `com.hans.todomd.share`
- `com.hans.todomd.widgets`

Download all three `.mobileprovision` files.

## Required GitHub secrets

Set these repository secrets before running the workflow:

- `APPLE_TEAM_ID`: Apple Developer team ID used for signing
- `APP_STORE_CONNECT_KEY_ID`: App Store Connect API key ID
- `APP_STORE_CONNECT_ISSUER_ID`: App Store Connect API issuer ID
- `APP_STORE_CONNECT_PRIVATE_KEY`: Contents of the `AuthKey_XXXXXX.p8` file
- `BUILD_CERTIFICATE_BASE64`: Base64-encoded Apple Distribution certificate `.p12`
- `P12_PASSWORD`: Password for the `.p12` certificate
- `KEYCHAIN_PASSWORD`: Temporary keychain password for the runner
- `APP_PROVISION_PROFILE_BASE64`: Base64-encoded App Store provisioning profile for `com.hans.todomd`
- `SHARE_PROVISION_PROFILE_BASE64`: Base64-encoded App Store provisioning profile for `com.hans.todomd.share`
- `WIDGETS_PROVISION_PROFILE_BASE64`: Base64-encoded App Store provisioning profile for `com.hans.todomd.widgets`

`KEYCHAIN_PASSWORD` does not come from Apple. It can be any strong random string used only for the temporary keychain on the GitHub runner.

## Loading secrets into GitHub

You can paste values in the GitHub web UI under `Settings -> Secrets and variables -> Actions`, or load them with `gh secret set`.

Examples:

```bash
gh secret set APPLE_TEAM_ID
gh secret set APP_STORE_CONNECT_KEY_ID
gh secret set APP_STORE_CONNECT_ISSUER_ID
gh secret set P12_PASSWORD
gh secret set KEYCHAIN_PASSWORD
gh secret set APP_STORE_CONNECT_PRIVATE_KEY < AuthKey_ABC123XYZ.p8
base64 < TodoMDDistribution.p12 | tr -d '\n' | gh secret set BUILD_CERTIFICATE_BASE64
base64 < TodoMDApp.mobileprovision | tr -d '\n' | gh secret set APP_PROVISION_PROFILE_BASE64
base64 < TodoMDShareExtension.mobileprovision | tr -d '\n' | gh secret set SHARE_PROVISION_PROFILE_BASE64
base64 < TodoMDWidgets.mobileprovision | tr -d '\n' | gh secret set WIDGETS_PROVISION_PROFILE_BASE64
```

## Preflight checks before the first release

- Confirm `xcodegen generate` and `swift test` pass locally.
- Confirm the Apple Distribution certificate is present in your login keychain:

```bash
security find-identity -v -p codesigning
```

- Confirm each provisioning profile matches the expected bundle ID and app group:

```bash
security cms -D -i TodoMDApp.mobileprovision > /tmp/TodoMDApp-profile.plist
/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' /tmp/TodoMDApp-profile.plist
/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups' /tmp/TodoMDApp-profile.plist
```

For the main app profile, the `application-identifier` should end with `com.hans.todomd`. For the extension profiles, repeat the same check and confirm they end with `com.hans.todomd.share` and `com.hans.todomd.widgets`. All three profiles should include `group.com.hans.todomd`.

- In App Store Connect, confirm any required agreements are accepted. Missing legal agreements can block uploads even when signing is correct.

## How to run it

1. Open the `Release to TestFlight` workflow in GitHub Actions.
2. Click `Run workflow`.
3. Choose the `ref` you want to release. `main` is the default.
4. Leave `internal_only` enabled for the first smoke test if the build should stay limited to internal TestFlight testers.
5. Watch the `Install signing assets`, `Archive release build`, and `Upload archive to TestFlight` steps first. Those are the most likely failure points on the initial run.

After upload, App Store Connect still needs to process the build before it appears in TestFlight.

## First-run troubleshooting

- `No profiles for ... were found`:
  The installed provisioning profile does not match the bundle ID, or the profile secret is wired to the wrong target.

- `Provisioning profile ... doesn't include the ... certificate`:
  The profile was generated against a different distribution certificate than the `.p12` you exported.

- Entitlements or app group mismatch:
  The profile does not include `group.com.hans.todomd`, or one of the App IDs has App Groups disabled. Re-enable the capability, regenerate the profile, then update the GitHub secret.

- Authentication or upload permission failure:
  Recheck `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and the contents of `APP_STORE_CONNECT_PRIVATE_KEY`. Also confirm the App Store Connect account has API access enabled.

- Build number already used:
  The workflow uses the GitHub Actions run number for `CURRENT_PROJECT_VERSION`. If App Store Connect already has a higher build number for the same marketing version, either bump `MARKETING_VERSION` or adjust the workflow's build-number formula before retrying.

## Build number behavior

The workflow overrides `CURRENT_PROJECT_VERSION` during archive using the GitHub Actions run number, so each uploaded build gets a unique TestFlight build number without changing `project.yml`.

## Reference links

- [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/)
- [Register an app group](https://developer.apple.com/help/account/identifiers/register-an-app-group/)
- [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/)
- [Create a certificate signing request](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)
- [Certificates overview](https://developer.apple.com/help/account/certificates/certificates-overview/)
- [Create an App Store Connect provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)
- [App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)
- [Using secrets in GitHub Actions](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-what-your-workflow-does/using-secrets-in-github-actions)
