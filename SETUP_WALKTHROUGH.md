# DuEasy Pro Setup - Complete Walkthrough

Follow these steps **in order** to get everything working.

## Prerequisites

- [ ] macOS with Xcode 15+
- [ ] Active internet connection
- [ ] Credit card (for OpenAI API - you'll get $5 free credit)
- [ ] Apple Developer account (free is OK for testing)

---

## Part 1: OpenAI API Setup (10 minutes)

### Step 1.1: Create OpenAI Account

1. Go to: https://platform.openai.com/signup
2. Sign up with:
   - Email address, OR
   - Google account, OR
   - Microsoft account
3. Verify your email

### Step 1.2: Add Payment Method

1. Go to: https://platform.openai.com/account/billing
2. Click **"Add payment method"**
3. Enter credit card details
4. Note: You get **$5 free credit** to start
5. Set up billing alerts:
   - Click "Usage limits"
   - Set hard limit: $50/month (recommended)
   - Set email alert: $20/month

### Step 1.3: Generate API Key

1. Go to: https://platform.openai.com/api-keys
2. Click **"Create new secret key"**
3. Name it: `DuEasy Production`
4. Click **"Create secret key"**
5. **IMPORTANT**: Copy the key NOW (starts with `sk-proj-...`)
6. Save it somewhere safe - you won't see it again!

**Example key format:**
```
sk-proj-abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567
```

### Step 1.4: Verify API Key Works

Open Terminal and test:

```bash
# Replace YOUR_API_KEY with your actual key
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer sk-proj-YOUR_API_KEY_HERE"
```

You should see a JSON list of models. If you see an error, check your API key.

**✅ OpenAI Setup Complete!** Save your API key - we'll use it later.

---

## Part 2: Firebase Project Setup (15 minutes)

### Step 2.1: Create Firebase Project

1. Go to: https://console.firebase.google.com
2. Click **"Add project"** (or "Create a project")
3. Enter project name: `DuEasy` (or whatever you prefer)
4. Click **"Continue"**

### Step 2.2: Disable Google Analytics (Privacy)

1. **Uncheck** "Enable Google Analytics for this project"
   - We don't need analytics (privacy-first!)
2. Click **"Create project"**
3. Wait ~30 seconds for setup
4. Click **"Continue"**

### Step 2.3: Add iOS App to Firebase

1. In Firebase Console, click the **iOS icon** (⊕ icon)
2. Enter iOS bundle ID: `com.dueasy.app`
   - **IMPORTANT**: Must match your Xcode project
3. Enter App nickname: `DuEasy iOS`
4. Leave App Store ID blank
5. Click **"Register app"**

### Step 2.4: Download GoogleService-Info.plist

1. Click **"Download GoogleService-Info.plist"**
2. Save to your Downloads folder
3. **IMPORTANT**: Keep this file safe
4. Click **"Next"** → **"Next"** → **"Continue to console"**

**✅ Firebase Project Created!**

---

## Part 3: Enable Firebase Services (10 minutes)

### Step 3.1: Enable Authentication

1. In Firebase Console, click **"Authentication"** in left menu
2. Click **"Get started"**
3. Click on **"Sign-in method"** tab
4. Click **"Add new provider"**
5. Select **"Anonymous"** (for testing)
6. Toggle **"Enable"**
7. Click **"Save"**

**For Production (later):**
- Also enable **"Sign in with Apple"**
- Enter your Apple Team ID
- Configure Service ID

### Step 3.2: Upgrade to Blaze Plan (Required for Cloud Functions)

1. In Firebase Console, click **"Upgrade"** (bottom left)
2. Select **"Blaze (Pay as you go)"** plan
3. Click **"Continue"**
4. Select your billing account or create new one
5. Click **"Purchase"**

**Don't worry about costs:**
- Firebase free tier: 2M function calls/month (plenty!)
- You'll only pay for OpenAI API usage (~$0.01/document)
- Set budget alerts to be safe

### Step 3.3: Set Budget Alerts

1. Go to: https://console.cloud.google.com/billing
2. Select your Firebase project
3. Click **"Budgets & alerts"** in left menu
4. Click **"CREATE BUDGET"**
5. Set budget: $50/month
6. Set alert at: 50%, 90%, 100%
7. Enter your email
8. Click **"FINISH"**

**✅ Firebase Services Enabled!**

---

## Part 4: Add Firebase SDK to Xcode (5 minutes)

### Step 4.1: Open Xcode Project

```bash
cd /Users/bart/Documents/DuEasy
open DuEasy.xcodeproj
```

### Step 4.2: Add GoogleService-Info.plist

1. In Xcode, right-click on **"Dueasy_v2"** folder (in project navigator)
2. Select **"Add Files to Dueasy_v2..."**
3. Navigate to your Downloads folder
4. Select **GoogleService-Info.plist**
5. **CHECK** ✅ "Copy items if needed"
6. **CHECK** ✅ "Dueasy_v2" target
7. Click **"Add"**

**Verify**: GoogleService-Info.plist should now be visible in Xcode project navigator.

### Step 4.3: Add Firebase Packages via SPM

1. In Xcode, go to **File** → **Add Package Dependencies...**
2. In search box, paste:
   ```
   https://github.com/firebase/firebase-ios-sdk
   ```
3. Press Enter/Return
4. Wait for package to load (~10 seconds)
5. **Dependency Rule**: Select "Up to Next Major Version"
6. **Version**: Should show `11.0.0` or higher
7. Click **"Add Package"**

### Step 4.4: Select Firebase Products

When the product selection screen appears, select **ONLY** these:

- ✅ **FirebaseAuth**
- ✅ **FirebaseCore**
- ✅ **FirebaseFunctions**

**DO NOT select** (keep binary small):
- ❌ FirebaseAnalytics
- ❌ FirebaseFirestore
- ❌ FirebaseCrashlytics
- ❌ Anything else

Click **"Add Package"**

Wait for Xcode to download and integrate (~1-2 minutes).

### Step 4.5: Verify Installation

1. Press **Cmd+B** to build
2. You should see "Build Succeeded"
3. If you see errors, check the Troubleshooting section below

**✅ Firebase SDK Added to iOS App!**

---

## Part 5: Deploy Cloud Functions (15 minutes)

### Step 5.1: Install Firebase CLI

Open Terminal:

```bash
# Install Firebase CLI globally
npm install -g firebase-tools

# Verify installation
firebase --version
# Should show: 13.x.x or higher
```

If you don't have Node.js installed:

```bash
# Install Node.js via Homebrew
brew install node

# Or download from: https://nodejs.org
```

### Step 5.2: Login to Firebase

```bash
firebase login
```

This will:
1. Open browser window
2. Ask you to sign in with Google
3. Request permissions
4. Show "Success!" message

Close browser and return to Terminal.

### Step 5.3: Navigate to Functions Directory

```bash
cd /Users/bart/Documents/DuEasy/firebase_functions
```

### Step 5.4: Initialize Firebase Project

```bash
# Link to your Firebase project
firebase use --add
```

Select your project from the list (e.g., "DuEasy")
Give it an alias: `default`

### Step 5.5: Set Environment Variables

```bash
# Set your OpenAI API key (replace with YOUR key)
firebase functions:config:set openai.api_key="sk-proj-YOUR_KEY_HERE"

# Set OpenAI model
firebase functions:config:set openai.model="gpt-4o"

# Verify config
firebase functions:config:get
```

You should see:
```json
{
  "openai": {
    "api_key": "sk-proj-...",
    "model": "gpt-4o"
  }
}
```

### Step 5.6: Deploy Functions

**Option 1: Use deploy script (recommended)**

```bash
chmod +x deploy.sh
./deploy.sh
```

**Option 2: Manual deployment**

```bash
# Install dependencies
npm install

# Deploy
firebase deploy --only functions
```

**Deployment takes 2-3 minutes.** You'll see output like:

```
✔  functions[analyzeDocument(europe-west1)]: Successful create operation.
✔  functions[getSubscriptionStatus(europe-west1)]: Successful create operation.
✔  Deploy complete!
```

**Copy the function URLs** - you'll need them for testing.

**✅ Cloud Functions Deployed!**

---

## Part 6: Test Everything (10 minutes)

### Step 6.1: Test Firebase Emulator (Optional but Recommended)

```bash
# Start emulator
cd /Users/bart/Documents/DuEasy/firebase_functions
firebase emulators:start
```

You should see:
```
✔  functions[europe-west1-analyzeDocument]: http function initialized
✔  All emulators ready!
```

**Keep this terminal open** and open a new terminal tab for testing.

### Step 6.2: Test Cloud Functions Locally

In a **new terminal tab**:

```bash
cd /Users/bart/Documents/DuEasy/firebase_functions

# Make test script executable
chmod +x test_functions.sh

# Run tests against emulator
USE_EMULATOR=true ./test_functions.sh
```

You should see test results for Polish and English invoices.

**If tests pass**: ✅ Everything works!

### Step 6.3: Test Production Deployment

Stop the emulator (Ctrl+C in first terminal), then:

```bash
# Test against production
./test_functions.sh
```

**Note**: This will fail authentication (we haven't set up auth yet), but that's expected. You should see:
```
"error": "unauthenticated"
```

This is GOOD - it means the function is deployed and security is working!

### Step 6.4: Test iOS App with Pro Tier

1. Open Xcode
2. Find `Dueasy_v2App.swift` (or your main app file)
3. Add this code to initialize Firebase:

```swift
import SwiftUI
import SwiftData

@main
struct Dueasy_v2App: App {
    @State private var environment: AppEnvironment?

    init() {
        // Initialize Firebase for Pro tier
        Task { @MainActor in
            FirebaseConfigurator.shared.configure(for: .pro)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let environment = environment {
                MainTabView()
                    .environment(environment)
            } else {
                ProgressView()
                    .task {
                        await setupEnvironment()
                    }
            }
        }
    }

    @MainActor
    private func setupEnvironment() async {
        // Set up SwiftData
        let schema = Schema([
            FinanceDocument.self,
            VendorProfile.self,
            GlobalKeywordConfig.self,
            LearningData.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )

            let context = ModelContext(container)

            // Create environment with Pro tier
            environment = AppEnvironment(
                modelContext: context,
                tier: .pro  // ← Pro tier with Firebase!
            )

            // Run migrations
            try await environment?.runStartupMigrations()

        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
```

4. Build and run (Cmd+R)
5. Check Xcode console for:
   ```
   ✅ Firebase configured successfully
   ✅ AppEnvironment initialized for tier: Pro (Firebase active)
   ```

**✅ Everything Working!**

---

## Part 7: Create Test User & Test Full Flow (15 minutes)

### Step 7.1: Enable Anonymous Authentication in iOS

The app should automatically sign in anonymously when Pro tier is enabled.

Run the app and check console:
```
Firebase Auth: Anonymous sign-in enabled
User authenticated: [user-id]
```

### Step 7.2: Grant Test User Pro Subscription

For testing, manually grant Pro status:

1. Go to Firebase Console: https://console.firebase.google.com
2. Click **"Firestore Database"** in left menu
3. Click **"Create database"** (if first time)
   - Select **"Start in test mode"** (for now)
   - Select location: `europe-west1`
   - Click **"Enable"**
4. Click **"Start collection"**
   - Collection ID: `users`
   - Document ID: [your test user ID from console]
   - Add fields:
     ```
     subscription (map):
       tier: "pro"
       isActive: true
       expiresAt: null
       willAutoRenew: true
       isTrialPeriod: true
     ```
5. Click **"Save"**

### Step 7.3: Test Document Analysis

1. In the app, tap **"Add Document"**
2. Tap **"Scan Document"**
3. Take a photo of an invoice (or use a test image)
4. Watch the console:
   ```
   Local analysis confidence: 0.45
   Low confidence, requesting cloud assist
   Calling Firebase Function...
   Cloud assist successful
   ```

5. Check extracted fields - should be 99% accurate!

### Step 7.4: Verify Costs

1. Go to: https://platform.openai.com/usage
2. You should see 1 request
3. Cost should be ~$0.01

**✅ Full Pro Tier Working!**

---

## Troubleshooting

### Issue: "Module 'FirebaseAuth' not found"

**Solution:**
```bash
# In Xcode:
# 1. File → Packages → Reset Package Caches
# 2. Clean Build Folder (Cmd+Shift+K)
# 3. Build (Cmd+B)
```

### Issue: "GoogleService-Info.plist not found"

**Check 1:** Is file in Xcode project navigator?
**Check 2:** Right-click file → Show File Inspector → Is target checked?

**Fix:**
```bash
# Verify file exists
ls -la /Users/bart/Documents/DuEasy/Dueasy_v2/GoogleService-Info.plist

# If missing, re-download from Firebase Console
```

### Issue: "OpenAI API key invalid"

**Check:**
```bash
# Test API key
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer YOUR_KEY"
```

**Fix:**
- Generate new key at https://platform.openai.com/api-keys
- Update Firebase config:
  ```bash
  firebase functions:config:set openai.api_key="NEW_KEY"
  firebase deploy --only functions
  ```

### Issue: "Firebase Functions deploy failed"

**Common causes:**
1. Not logged in: `firebase login`
2. Wrong project: `firebase use --add`
3. Not on Blaze plan: Upgrade in console
4. Node.js too old: `node --version` (need 18+)

### Issue: "Build time too long"

**Optimization:**
1. Xcode → Preferences → Locations → Derived Data → Delete
2. Enable "Build Active Architecture Only" in Build Settings
3. Use physical device instead of simulator

### Issue: "App crashes on launch"

**Check console for:**
- Firebase configuration errors
- Missing GoogleService-Info.plist
- SwiftData schema issues

**Fix:**
- Verify Firebase initialization
- Check all files are in target
- Reset app data (delete app, reinstall)

---

## Next Steps

Now that everything is working:

### 1. Implement StoreKit Subscriptions

See: https://developer.apple.com/documentation/storekit

### 2. Test with Real Invoices

- Take 20+ photos of real invoices
- Compare local vs cloud accuracy
- Tune confidence thresholds if needed

### 3. Set Up Production Firestore Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### 4. Submit to App Store

- Create screenshots
- Write app description
- Set privacy labels
- Submit for review

---

## Summary

You've now set up:

✅ OpenAI API account & key
✅ Firebase project (Authentication, Functions, Firestore)
✅ Firebase SDK in Xcode
✅ Cloud Functions deployed
✅ Pro tier working end-to-end

**Total time**: ~1 hour
**Total cost**: $0 (using free tiers + credits)
**Ready for**: Production launch! 🚀

## Support

If you get stuck:
1. Check this guide's Troubleshooting section
2. Check Firebase logs: `firebase functions:log`
3. Check OpenAI status: https://status.openai.com
4. Open GitHub issue with error details
