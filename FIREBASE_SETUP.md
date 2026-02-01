# Firebase Setup Guide for DuEasy Pro Tier

This guide explains how to set up Firebase for DuEasy's Pro tier features (cloud AI analysis, cloud vault, subscription management).

## Prerequisites

- Xcode 15.0+
- iOS 26.0+ deployment target
- Active Apple Developer account (for Sign in with Apple)
- Firebase account (free tier works for development)

## Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Click "Add project" or select existing project
3. Enter project name (e.g., "DuEasy")
4. Disable Google Analytics (optional, we don't use it for privacy)
5. Click "Create project"

## Step 2: Add iOS App to Firebase

1. In Firebase Console, click "Add app" → iOS
2. Enter iOS bundle ID: `com.dueasy.app`
3. Enter App nickname: `DuEasy iOS`
4. Leave App Store ID blank (not published yet)
5. Click "Register app"
6. Download `GoogleService-Info.plist`
7. Click "Next" → "Next" → "Continue to console"

## Step 3: Add GoogleService-Info.plist to Xcode

1. In Xcode, right-click on `Dueasy_v2` folder
2. Select "Add Files to Dueasy_v2..."
3. Select the downloaded `GoogleService-Info.plist`
4. **Important**: Check "Copy items if needed"
5. **Important**: Select target "Dueasy_v2"
6. Click "Add"

**Security Note**: Add `GoogleService-Info.plist` to `.gitignore` to avoid committing Firebase credentials to version control.

## Step 4: Add Firebase SDK via Swift Package Manager

1. In Xcode, go to **File** → **Add Package Dependencies...**
2. Enter package URL: `https://github.com/firebase/firebase-ios-sdk`
3. Select version: **11.0.0** or later
4. Click "Add Package"
5. Select the following products to add:
   - ✅ **FirebaseAuth** (for authentication)
   - ✅ **FirebaseFunctions** (for cloud AI integration)
   - ✅ **FirebaseCore** (required dependency)
6. Click "Add Package"

**Do NOT add** (to minimize binary size):
- ❌ FirebaseAnalytics (we don't track users)
- ❌ FirebaseFirestore (we use local SwiftData)
- ❌ FirebaseCrashlytics (optional, can add later)
- ❌ FirebaseMessaging (not needed for MVP)

## Step 5: Enable Firebase Services

### Authentication

1. In Firebase Console, go to **Authentication**
2. Click "Get started"
3. Enable **Sign in with Apple**:
   - Click "Sign in with Apple" provider
   - Click "Enable"
   - Enter your Apple Developer Team ID
   - Add Service ID (optional for web)
   - Click "Save"

### Cloud Functions

1. In Firebase Console, go to **Functions**
2. Click "Get started"
3. Upgrade to **Blaze (pay-as-you-go)** plan
   - Required for outbound API calls (OpenAI)
   - Free tier: 2M invocations/month
   - You'll only pay for OpenAI API usage

## Step 6: Deploy Cloud Functions (Backend)

See [BACKEND_DEPLOYMENT.md](./BACKEND_DEPLOYMENT.md) for deploying the OpenAI analysis functions.

Quick start:

```bash
cd firebase_functions
npm install
firebase deploy --only functions
```

Required environment variables for Cloud Functions:
```bash
firebase functions:config:set openai.api_key="sk-..." openai.model="gpt-4o"
```

## Step 7: Configure App for Pro Tier

### Development/Testing

To test with Firebase in development, change the AppEnvironment initialization in your app entry point:

```swift
// Dueasy_v2App.swift
@main
struct Dueasy_v2App: App {
    @State private var environment: AppEnvironment?

    var body: some Scene {
        WindowGroup {
            if let environment = environment {
                MainTabView()
                    .environment(environment)
            } else {
                ProgressView()
                    .task {
                        // Initialize Firebase BEFORE AppEnvironment
                        FirebaseConfigurator.shared.configure(for: .pro)

                        // Create environment with Pro tier
                        let context = // ... your ModelContext setup
                        environment = AppEnvironment(modelContext: context, tier: .pro)
                    }
            }
        }
    }
}
```

### Production

In production, tier selection will be determined by subscription status:

1. User starts with free tier
2. User purchases Pro subscription via in-app purchase
3. App verifies subscription with Firebase Functions
4. AppEnvironment switches to Pro tier services

## Step 8: Verify Setup

Build and run the app. Check Xcode console for:

```
✅ Firebase configured successfully
✅ AppEnvironment initialized for tier: Pro (Firebase active)
```

If you see warnings:
```
⚠️ Firebase: GoogleService-Info.plist not found
```
→ Check that GoogleService-Info.plist is added to Xcode project target

```
⚠️ Firebase: SDK not available
```
→ Check that Firebase packages are added via Swift Package Manager

## Troubleshooting

### "Module 'FirebaseAuth' not found"

1. Clean build folder: Cmd+Shift+K
2. Reset package caches: File → Packages → Reset Package Caches
3. Rebuild: Cmd+B

### "Firebase not configured"

1. Verify GoogleService-Info.plist is in the app bundle
2. Verify `FirebaseConfigurator.shared.configure()` is called before using Firebase services
3. Check Firebase Console for correct bundle ID

### Sign in with Apple fails

1. Enable "Sign In with Apple" capability in Xcode
2. Verify Team ID is correct in Firebase Console
3. Check that Sign in with Apple is enabled in Apple Developer Portal

## Privacy & Security

- **Local-first**: Free tier works 100% offline, no Firebase needed
- **Data minimization**: We only send OCR text to cloud, never full images (privacy-first)
- **Encryption**: All cloud data encrypted in transit (TLS) and at rest (AES-256)
- **Zero PII logs**: No personally identifiable information logged on backend
- **GDPR compliance**: European users can use free tier (100% local)

## Cost Estimates

Firebase costs for DuEasy Pro tier:

- **Authentication**: Free (unlimited)
- **Cloud Functions**: $0.40 per 1M invocations (2M free/month)
- **OpenAI API**: ~$0.01 per document analyzed (gpt-4o)
- **Bandwidth**: ~$0.12 per GB (generous free tier)

**Estimated cost per Pro user**: $0.50-$2.00/month depending on usage.

## Support

For issues with Firebase setup, check:
- [Firebase iOS Documentation](https://firebase.google.com/docs/ios/setup)
- [Firebase Support](https://firebase.google.com/support)
- DuEasy Issues: https://github.com/your-repo/dueasy/issues
