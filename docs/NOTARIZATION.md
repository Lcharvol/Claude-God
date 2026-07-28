# Notarization Setup

The GitHub Actions workflow (`.github/workflows/build.yml`) transparently upgrades from ad-hoc signing to full Developer ID signing + Apple notarization the moment all five secrets below are set on the repository. Nothing else needs to change — the workflow detects the presence of the secrets and switches modes automatically. Until then, releases stay ad-hoc signed exactly like today (users must run `xattr -cr /Applications/Claude\ God.app` after first launch).

## Why notarize

- Removes the "Claude God can't be opened because Apple cannot check it for malicious software" dialog on first launch.
- Removes the `xattr -cr` step from the install instructions.
- Recommended by AlternativeTo, MacMenuBar.com and other listings that filter out unnotarized apps.

Cost: **$99/year** for an Apple Developer Program membership. No cost per notarization.

## One-time Apple side

1. **Enroll in the Apple Developer Program** at https://developer.apple.com/programs/enroll/. Individual enrollment (~48h approval) is enough.

2. **Create a Developer ID Application certificate** in Xcode:
   - Open Xcode → Settings → Accounts → your Apple ID → Manage Certificates
   - Click `+` → **Developer ID Application**
   - Right-click the new certificate → Export Certificate → save as `.p12` with a password
   - Note the "Common name" — it looks like `Developer ID Application: Lucas Charvolin (ABCD123456)`

3. **Find your Team ID** at https://developer.apple.com/account → Membership → Team ID (10-character string like `ABCD123456`).

4. **Create an app-specific password** at https://appleid.apple.com/account/manage → Sign-In and Security → App-Specific Passwords → Generate. Label it "notarytool". Save the resulting password (looks like `abcd-efgh-ijkl-mnop`).

## GitHub secrets to set

Go to `Settings → Secrets and variables → Actions → New repository secret` and add all five:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_APPLICATION` | Full common name from step 2, e.g. `Developer ID Application: Lucas Charvolin (ABCD123456)` |
| `APPLE_CERT_P12_BASE64` | The `.p12` file base64-encoded: `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERT_PASSWORD` | The password you set when exporting the `.p12` |
| `APPLE_ID` | Your Apple ID email (the one enrolled in the Developer Program) |
| `APPLE_TEAM_ID` | The 10-character Team ID from step 3 |
| `APPLE_APP_PASSWORD` | The app-specific password from step 4 (with dashes) |

Once all six are set, the next `git push origin vX.Y.Z` will produce a notarized DMG. You can verify from the workflow logs — you'll see `🔐 Notarized signing enabled` instead of `⚠ Notarization secrets not set`.

## Verifying a released DMG

```bash
# Should print "accepted" and "Notarized Developer ID"
spctl -a -vvv -t install /path/to/ClaudeGod.dmg

# Should print a stapled ticket
stapler validate /path/to/ClaudeGod.dmg
```

## Troubleshooting

- **`No signing certificate "Developer ID Application" found`** during build → the `.p12` didn't import. Check `APPLE_CERT_P12_BASE64` is a valid base64 encoding of a real `.p12` file (not the `.cer` — you need the private key too).
- **notarytool `Invalid Credentials`** → double-check `APPLE_ID` matches the Apple ID that owns the Developer account and `APPLE_APP_PASSWORD` was generated at appleid.apple.com (not a normal password).
- **notarytool `Team is not in a valid state`** → your Developer Program membership lapsed or is being renewed. Renew at developer.apple.com.
- **Notarization succeeds but Gatekeeper still complains** → check the workflow log for `stapler staple` errors. The ticket has to be stapled or offline first-launch users won't see it.

## Removing notarization

Delete any one of the five secrets and the next release automatically falls back to ad-hoc signing. Existing notarized DMGs stay notarized forever — Apple doesn't retract tickets.
