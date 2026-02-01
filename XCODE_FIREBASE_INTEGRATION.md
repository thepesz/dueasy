# Xcode Firebase SDK Integration Guide

This guide shows how to add Firebase SDK packages to your Xcode project for DuEasy Pro tier features.

## Method 1: Swift Package Manager (Recommended)

### Step 1: Open Package Dependencies

1. Open `DuEasy.xcodeproj` in Xcode
2. Go to **File** → **Add Package Dependencies...**
3. Or: Select project in navigator → **Package Dependencies** tab → Click **+**

### Step 2: Add Firebase iOS SDK

1. In the search box, enter:
   ```
   https://github.com/firebase/firebase-ios-sdk
   ```

2. Select the repository when it appears

3. **Dependency Rule**: Select "Up to Next Major Version"
   - Version: `11.0.0` or later
   - This ensures you get compatible updates

4. Click **Add Package**

### Step 3: Select Products

When prompted, select **only** these products:

- ✅ **FirebaseAuth** - For user authentication
- ✅ **FirebaseFunctions** - For cloud functions
- ✅ **FirebaseCore** - Required base library

**Do NOT add** (keep binary size small):
- ❌ FirebaseAnalytics
- ❌ FirebaseFirestore (we use SwiftData)
- ❌ FirebaseCrashlytics (optional, add later if needed)
- ❌ FirebaseMessaging (not needed)
- ❌ FirebaseStorage (not needed)
- ❌ FirebaseDatabase (not needed)

### Step 4: Add to Target

Make sure packages are added to the **Dueasy_v2** target.

Click **Add Package**.

Xcode will download and integrate the packages (may take 1-2 minutes).

## Method 2: CocoaPods (Alternative)

If you prefer CocoaPods:

### Step 1: Install CocoaPods

```bash
sudo gem install cocoapods
```

### Step 2: Create Podfile

```bash
cd /path/to/DuEasy
pod init
```

### Step 3: Edit Podfile

```ruby
platform :ios, '26.0'

target 'Dueasy_v2' do
  use_frameworks!

  # Firebase
  pod 'Firebase/Auth'
  pod 'Firebase/Functions'
  pod 'Firebase/Core'
end
```

### Step 4: Install

```bash
pod install
```

**Important**: From now on, open `DuEasy.xcworkspace` instead of `.xcodeproj`.

## Verify Installation

### Build Test

1. In Xcode, press **Cmd+B** to build
2. You should see no errors
3. Look for "Build Succeeded" message

### Import Test

Add to any Swift file:

```swift
import FirebaseCore
import FirebaseAuth
import FirebaseFunctions
```

If no errors appear, Firebase is correctly integrated!

## Initialize Firebase

### Step 1: Add GoogleService-Info.plist

1. Download from Firebase Console (see FIREBASE_SETUP.md)
2. Drag into Xcode project navigator
3. **Important**: Check "Copy items if needed"
4. **Important**: Select target "Dueasy_v2"
5. Verify it appears in project navigator

### Step 2: Initialize in App

The app is already set up to initialize Firebase automatically!

`FirebaseConfigurator.swift` handles initialization:

```swift
// Called automatically on app launch
FirebaseConfigurator.shared.configure(for: appTier)
```

### Step 3: Test Tier Selection

To test Pro tier with Firebase:

```swift
// In Dueasy_v2App.swift or main app entry point
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
                        let container = // ... ModelContainer setup
                        let context = ModelContext(container)

                        // Create environment with Pro tier
                        environment = AppEnvironment(
                            modelContext: context,
                            tier: .pro  // ← Pro tier!
                        )
                    }
            }
        }
    }
}
```

## Troubleshooting

### "Module 'FirebaseAuth' not found"

**Solution 1**: Clean build
```
Cmd+Shift+K (Clean Build Folder)
Cmd+B (Build)
```

**Solution 2**: Reset package caches
```
File → Packages → Reset Package Caches
Cmd+B
```

**Solution 3**: Delete DerivedData
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```
Then rebuild in Xcode.

### "GoogleService-Info.plist not found"

**Check 1**: Is file in project navigator?
- Should be visible in Xcode sidebar

**Check 2**: Is file in target?
- Select GoogleService-Info.plist
- Check "Target Membership" in File Inspector (right panel)
- Ensure "Dueasy_v2" is checked

**Check 3**: Is file in correct location?
```bash
find /Users/bart/Documents/DuEasy -name "GoogleService-Info.plist"
```

Should be in project root or Dueasy_v2 folder.

### "Firebase not configured" at runtime

**Check initialization**:
```swift
// In FirebaseConfigurator.swift
print("Firebase configured: \(FirebaseConfigurator.shared.isConfigured)")
```

**Check logs**:
Look for:
```
✅ Firebase configured successfully
```

If you see:
```
⚠️ Firebase: GoogleService-Info.plist not found
```

→ GoogleService-Info.plist is not in the app bundle.

### Build time increased significantly

Firebase adds ~5-10MB to binary size. If build time is too long:

**Optimize**:
1. Use physical device instead of simulator (faster)
2. Enable "Build Active Architecture Only" (Debug)
3. Consider removing FirebaseCore if only testing locally

### Linker errors

If you see:
```
Undefined symbol: _OBJC_CLASS_$_FIRApp
```

**Solution**: Make sure you added packages to the correct target.

File → Project → Targets → Dueasy_v2 → General → Frameworks, Libraries

Firebase packages should be listed.

## Next Steps

After successful integration:

1. ✅ Firebase SDK installed
2. ✅ GoogleService-Info.plist added
3. ✅ App builds successfully
4. → Deploy Cloud Functions (see BACKEND_DEPLOYMENT.md)
5. → Test Pro tier features
6. → Implement StoreKit subscriptions

## Verification Checklist

- [ ] Firebase packages appear in Package Dependencies
- [ ] GoogleService-Info.plist in project
- [ ] Build succeeds (Cmd+B)
- [ ] Console shows "Firebase configured successfully"
- [ ] AppEnvironment initializes with Pro tier
- [ ] No runtime errors on launch

## Minimum iOS Version

Firebase requires:
- **iOS 13.0+** minimum
- **iOS 26.0+** for DuEasy (our deployment target)

No issues with compatibility ✅

## Binary Size Impact

Adding Firebase:
- **FirebaseCore**: ~2MB
- **FirebaseAuth**: ~3MB
- **FirebaseFunctions**: ~2MB
- **Total**: ~7MB added to app

Free tier (without Firebase): ~10MB
Pro tier (with Firebase): ~17MB

This is acceptable for a Pro tier feature.

## Privacy Impact

Firebase SDKs:
- ✅ No analytics by default (we didn't add FirebaseAnalytics)
- ✅ No automatic data collection
- ✅ Only Auth + Functions (explicit user actions)
- ✅ All data in EU region (GDPR compliant)

## Support

- Swift Package Manager: https://www.swift.org/package-manager/
- Firebase iOS Setup: https://firebase.google.com/docs/ios/setup
- Xcode Help: https://developer.apple.com/documentation/xcode

For DuEasy-specific issues:
- Check FIREBASE_SETUP.md
- Open GitHub issue
