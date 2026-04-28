# GitHub Secrets Setup — LinguaBridge Code Signing

Jobs 1 (lint) and 2 (build-test) need **no secrets at all** — they build
without code signing using the iOS Simulator.

Job 3 (archive-ipa) needs 4 secrets. This guide walks through creating them.

---

## What you need before starting

- Your iPhone XR connected to your Mac
- Xcode open and signed in with your Apple ID
- A terminal window open

---

## Secret 1 — BUILD_CERTIFICATE_BASE64

This is your iOS development signing certificate exported as a base64 string.

### Step A — Export certificate from Keychain Access

1. Open **Keychain Access** on your Mac (Spotlight → "Keychain Access")
2. In the sidebar, click **My Certificates**
3. Find: `Apple Development: your@email.com (XXXXXXXXXX)`
4. Right-click it → **Export "Apple Development: ..."**
5. Format: **Personal Information Exchange (.p12)**
6. Save as `cert.p12` to your Desktop
7. Set a password when prompted — **remember this for Secret 2**

> If you don't see it: open Xcode → Preferences → Accounts → select your
> Apple ID → click **Download Manual Profiles** — then check Keychain again.

### Step B — Convert to base64

```bash
# In Terminal:
base64 -i ~/Desktop/cert.p12 | pbcopy
```

This copies the base64 string to your clipboard.

### Step C — Add to GitHub

1. Go to your GitHub repo → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Name: `BUILD_CERTIFICATE_BASE64`
4. Value: paste from clipboard
5. Click **Add secret**

---

## Secret 2 — P12_PASSWORD

The password you set when exporting the `.p12` file in Secret 1 Step A.

1. **New repository secret**
2. Name: `P12_PASSWORD`
3. Value: the password you chose
4. Click **Add secret**

---

## Secret 3 — BUILD_PROVISION_PROFILE_BASE64

Your iOS development provisioning profile as a base64 string.

### Step A — Find the provisioning profile

Xcode stores profiles here:

```bash
ls ~/Library/MobileDevice/Provisioning\ Profiles/
```

To find the right one — run this in Terminal to list all profiles with names:

```bash
for f in ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision; do
  echo "─────────────────────────────────"
  echo "File: $f"
  /usr/libexec/PlistBuddy -c 'Print :Name' /dev/stdin \
    <<< "$(security cms -D -i "$f" 2>/dev/null)" 2>/dev/null
  /usr/libexec/PlistBuddy -c 'Print :AppIDName' /dev/stdin \
    <<< "$(security cms -D -i "$f" 2>/dev/null)" 2>/dev/null
done
```

Look for one that mentions `LinguaBridge`.

If you don't see one, generate it in Xcode first:
1. Open Xcode → **LinguaBridge** target → **Signing & Capabilities**
2. Make sure **Automatically manage signing** is ticked
3. Connect your iPhone XR via USB → press **⌘R** to build once
4. Xcode will auto-create the provisioning profile
5. Run the Terminal command above again to find it

### Step B — Convert to base64

```bash
# Replace <UUID> with the actual filename you found above
base64 -i ~/Library/MobileDevice/Provisioning\ Profiles/<UUID>.mobileprovision | pbcopy
```

### Step C — Add to GitHub

1. **New repository secret**
2. Name: `BUILD_PROVISION_PROFILE_BASE64`
3. Value: paste from clipboard
4. Click **Add secret**

---

## Secret 4 — KEYCHAIN_PASSWORD

This is just a password the CI runner uses to create a temporary keychain.
It is never stored anywhere permanently — it's discarded at the end of each run.

Choose any strong password (e.g. generate one):

```bash
openssl rand -base64 20 | pbcopy   # copies a random password to clipboard
```

1. **New repository secret**
2. Name: `KEYCHAIN_PASSWORD`
3. Value: paste the random password
4. Click **Add secret**

---

## Verify all 4 secrets are set

In your GitHub repo → **Settings** → **Secrets and variables** → **Actions**,
you should see all four listed (values are hidden):

```
BUILD_CERTIFICATE_BASE64      ✓
P12_PASSWORD                  ✓
BUILD_PROVISION_PROFILE_BASE64 ✓
KEYCHAIN_PASSWORD             ✓
```

---

## Running the workflow manually

1. Go to your GitHub repo → **Actions** tab
2. In the left sidebar, click **LinguaBridge CI/CD**
3. Click the **Run workflow ▼** button (top right of the runs list)
4. Choose options:
   - **Export IPA after build**: tick this to run Job 3
   - **Run unit tests**: untick to skip tests (faster)
   - **Log level**: `verbose` for debugging build errors
5. Click the green **Run workflow** button

The workflow button only appears because of the `workflow_dispatch` block
in the YAML file — no extra configuration needed.

---

## Downloading the IPA from GitHub

After Job 3 completes:

1. Click the completed workflow run in the Actions tab
2. Scroll to the **Artifacts** section at the bottom
3. Click `LinguaBridge-IPA-{run_number}` to download a `.zip`
4. Unzip it — you'll find `LinguaBridge.ipa` and `BUILD_INFO.txt`
5. Install with Apple Configurator 2:
   - Connect iPhone XR via USB
   - Right-click device → Add → Apps → Choose from Mac → select the `.ipa`

---

## Troubleshooting

**"No signing certificate found"**
→ The certificate in the secret expired or was exported incorrectly.
   Re-export from Keychain Access and update the secret.

**"Missing provisioning profile"**
→ The profile doesn't match the bundle ID in your Xcode project.
   Check that the bundle ID in Xcode matches what's in the profile.

**"Profile expired"**
→ Free Apple ID profiles expire every 7 days and certificates every 1 year.
   Reconnect your iPhone in Xcode → ⌘R → re-export the profile.

**Job 3 skipped on push to main**
→ Job 3 only runs if secrets are set. If any of the 4 secrets are missing
   or empty, the signing step will fail. Check all 4 are present in Settings.

**"xcodebuild: error: 'LinguaBridge.xcodeproj' not found"**
→ The `.xcodeproj` file must be at the root of your repository (same level
   as the `.github` folder), not in a subdirectory.
