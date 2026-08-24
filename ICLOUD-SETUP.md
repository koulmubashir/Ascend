# Enabling iCloud backup

`CloudBackup.swift` is written and wired into Settings, but the entitlement is
**not** in `GymTracker.entitlements`.

Why: `com.apple.developer.ubiquity-kvstore-identifier` requires a provisioning
profile. With no signing certificate on this machine, adding it broke signing
for every target — including the simulator builds used for everything else.

## To turn it on, once your iPhone is connected and signing works

Add to `GymTracker/GymTracker.entitlements`:

```xml
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
```

Then in Xcode, select the GymTracker target → Signing & Capabilities → **+
Capability** → **iCloud** → tick **Key-value storage**.

Until then `CloudBackup.isAvailable` returns false, the buttons report "Sign in
to iCloud", and nothing is lost — file export still works and is unaffected.
