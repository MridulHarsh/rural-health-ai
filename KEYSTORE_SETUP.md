# Release Keystore Setup (one-time, ~5 min)

The CI workflow at [.github/workflows/build-apk.yml](.github/workflows/build-apk.yml) builds an APK on every push. By default it signs with Android's debug keystore — fine for hackathon demos, but Google Play and most internal app-distribution tools (Firebase App Distribution, Diawi, Huawei AppGallery) reject debug-signed artifacts.

When you're ready to ship through one of those channels, run through this page once. No code change needed — as soon as the four secrets below are set on the repo, the next CI build will sign with your real upload key; when they're absent it falls through to debug signing. Both paths work.

## 1 · Generate a release keystore

Pick a password and remember it (use a password manager). The 25-year validity matches Google Play's requirement.

```bash
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 9125 \
  -alias upload \
  -storepass <YOUR_STORE_PASSWORD> \
  -keypass <YOUR_KEY_PASSWORD>
```

`keytool` will prompt for your name, org, city, country. These go into the certificate and are visible to anyone who inspects your APK — keep them professional.

**Back up `upload-keystore.jks` somewhere safe** (encrypted drive, 1Password vault, etc.). If you lose this file you cannot update the app on Google Play — you'd have to publish a new listing with a new package name.

## 2 · Base64-encode the keystore for transport

GitHub Actions secrets are text-only, so we base64 the binary keystore:

```bash
base64 -i upload-keystore.jks | pbcopy
```

(On Linux use `base64 upload-keystore.jks | xclip -selection clipboard`.)

The whole blob (one big line) is now in your clipboard. Don't paste it into Slack or commit it anywhere.

## 3 · Set four GitHub repo secrets

Go to the repo on GitHub → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Add exactly these four:

| Secret name | Value |
|---|---|
| `KEYSTORE_BASE64` | The base64 blob you just copied in step 2 |
| `KEYSTORE_PASSWORD` | Your `<YOUR_STORE_PASSWORD>` from step 1 |
| `KEY_ALIAS` | `upload` (or whatever alias you chose in step 1) |
| `KEY_PASSWORD` | Your `<YOUR_KEY_PASSWORD>` from step 1 |

The names must match exactly — the workflow's `env:` block reads them by name.

## 4 · Verify on the next CI run

Push any commit (even a whitespace change). On the **Actions** tab you should now see a **"Configure release signing"** step running before the build. If that step is skipped, one of the four secrets is missing or mis-named — the `if: ${{ env.KEYSTORE_BASE64 != '' }}` guard evaluates false.

Download the resulting APK artifact and verify it's signed with your key, not debug:

```bash
apksigner verify --verbose app-release.apk | grep -i 'Signer'
```

You should see your certificate's DN (the name/org you typed into `keytool`). If it shows `CN=Android Debug` that means the signing step didn't run — check secret names in step 3.

## 5 · Local signed builds (optional)

To sign locally the same way CI does, drop `upload-keystore.jks` into `android_app/android/app/` and create `android_app/android/keystore.properties`:

```properties
storeFile=app/upload-keystore.jks
storePassword=<YOUR_STORE_PASSWORD>
keyAlias=upload
keyPassword=<YOUR_KEY_PASSWORD>
```

Both files are gitignored — they'll never get pushed. Now `~/development/flutter/bin/flutter build apk --release` produces a signed APK identical to CI's output.

## Troubleshooting

| Symptom | Fix |
|---|---|
| CI still shows "signed with debug keystore" | One of the four secrets is missing. Go to Settings → Secrets and recheck all four names — they're case-sensitive. |
| `keytool: command not found` | Install a JDK: `brew install openjdk@17`. Then `export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"`. |
| `base64: illegal option` on macOS | macOS's `base64` uses `-i` for input; GNU uses nothing. Check you're running macOS's version (`which base64`). |
| Google Play rejects with "keystore does not match" | You're uploading with a different key than the one already on that listing. Either recover the original key, or use Play App Signing key upgrade (one-time, Google-side). |
| Build fails with "Keystore file ... not found" | The workflow step ran but base64 decode produced an invalid file. Regenerate the `KEYSTORE_BASE64` secret — `pbcopy` sometimes drops trailing newlines on very large inputs. Paste into a file and inspect it before setting the secret. |
