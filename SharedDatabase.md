# Shared CloudKit Database with IceCream

IceCream now supports CloudKit's **shared database**, letting owners share entire Realm object collections with other iCloud users. Participants sync shared records into their own local Realm automatically.

---

## How it works

CloudKit's sharing model has two sides:

| Role | What they do |
|---|---|
| **Owner** | Creates a `CKShare` for a record zone (= all objects of one type). Sends the share URL to friends. Uses their normal `.private` `SyncEngine`. |
| **Participant** | Accepts the invitation. Creates a second `SyncEngine` with `databaseScope: .shared`. Shared records land in their local Realm. |

Zone-level sharing (`CKShare(recordZoneID:)`) requires **iOS 15 / macOS 12** or later. The participant-side sync works on the same deployment target as the rest of IceCream.

---

## Step 1 – Define your model (unchanged)

```swift
import RealmSwift
import IceCream

class Dog: Object, CKRecordConvertible, CKRecordRecoverable {
    @objc dynamic var id      = UUID().uuidString
    @objc dynamic var name    = ""
    @objc dynamic var isDeleted = false

    override static func primaryKey() -> String? { "id" }
}
```

No changes to your model are required. `databaseScope` defaults to `.private`, which is correct — the owner's model definition is reused by both sides.

---

## Step 2 – Owner: set up the normal private engine

```swift
// AppDelegate or your sync manager — nothing new here
let privateEngine = SyncEngine(
    objects: [SyncObject(type: Dog.self)],
    databaseScope: .private
)
```

---

## Step 3 – Owner: create a share and send the URL

```swift
// iOS 15+ / macOS 12+ only
if #available(iOS 15.0, macOS 12.0, *) {
    privateEngine.createShare(
        type: Dog.self,
        publicPermission: .readOnly   // or .readWrite
    ) { share, url, error in
        if let error = error {
            print("Share failed:", error)
            return
        }
        guard let url = url else { return }
        // Send `url` to the participant via Messages, Mail, etc.
        print("Share URL:", url)
    }
}
```

`publicPermission` controls what anyone with the link can do:

| Value | Effect |
|---|---|
| `.readOnly` (default) | Participants can read; writes are rejected by CloudKit |
| `.readWrite` | Participants can create, update, and delete records |
| `.none` | Only explicitly invited participants (requires using `UICloudSharingController`) |

> **Zone scope:** the share covers all `Dog` records — you cannot share individual records this way. If you need per-record sharing, use `CKShare(rootRecord:)` instead (not managed by IceCream).

---

## Step 4 – Participant: create the shared engine

The participant creates a **second** `SyncEngine` for the same model type but pointing at the shared database. Keep it alive for the lifetime of the app (e.g. as a property on `AppDelegate` or a singleton).

```swift
// Participant's AppDelegate or sync manager
let sharedEngine = SyncEngine(
    objects: [SyncObject(type: Dog.self)],
    databaseScope: .shared
)
```

> The two engines (owner's private, participant's shared) are completely independent. Each maintains its own change tokens and subscriptions.

---

## Step 5 – Participant: handle the share invitation

When the user taps the share link, the system calls one of these methods depending on your app type.

### UIKit – `UIApplicationDelegate`

```swift
func application(
    _ application: UIApplication,
    userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
) {
    sharedEngine.acceptShare(metadata: metadata) { error in
        if let error = error {
            print("Accept failed:", error)
        } else {
            print("Shared Dogs are now in Realm!")
        }
    }
}
```

### SwiftUI – `onContinueUserActivity`

```swift
@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onContinueUserActivity(
                    NSUserActivityTypes.cloudKitShareMetadataType
                ) { activity in
                    guard
                        let metadata = activity.userInfo?["CKShareMetadata"]
                            as? CKShare.Metadata
                    else { return }
                    delegate.sharedEngine.acceptShare(metadata: metadata) { _ in }
                }
        }
    }
}
```

`acceptShare` calls `CKContainer.accept(_:)` and then immediately fetches all changed records from `sharedCloudDatabase` into Realm.

---

## Step 6 – Read shared records from Realm

After acceptance, shared records are written into your normal Realm (the same configuration passed to `SyncObject`). Query them exactly as you would locally-owned records:

```swift
let realm = try! Realm()
let dogs = realm.objects(Dog.self)
// Includes both your own Dogs and Dogs shared with you
```

If you need to distinguish ownership, compare the record's zone `ownerName` against `CKCurrentUserDefaultName`, or add an `ownerID` property to your model and set it when creating records.

---

## Step 7 – Write-back (read-write shares only)

If the owner granted `.readWrite`, the participant's normal Realm write will propagate to CloudKit:

```swift
let realm = try! Realm()
try! realm.write {
    let dog = realm.objects(Dog.self).first!
    dog.name = "Max"
}
// SyncObject observes the Realm change → pipeToEngine fires →
// SharedDatabaseManager rewrites the zone ID to the real owner zone →
// CKModifyRecordsOperation is submitted to sharedCloudDatabase
```

If the share is read-only, CloudKit returns a `permissionFailure` error and the write is silently dropped. The local Realm change will persist until the next fetch overwrites it.

---

## Step 8 – Push notifications (background sync)

Add the `CKDatabaseSubscription` capability so the participant's device wakes up when the owner changes a record.

### Xcode Signing & Capabilities

Enable both:
- **Push Notifications**
- **CloudKit** (with your container)

### Handle the silent push

```swift
// AppDelegate
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)

    // IceCream posts Notifications.cloudKitDataDidChangeRemotely which triggers
    // both the private and shared engines automatically.
    NotificationCenter.default.post(
        name: Notifications.cloudKitDataDidChangeRemotely.name,
        object: nil
    )
    completionHandler(.newData)
}
```

Both `SyncEngine` instances observe `Notifications.cloudKitDataDidChangeRemotely` and will each call their own `fetchChangesInDatabase` when it fires.

---

## Complete example

```swift
// MARK: - AppDelegate.swift

import UIKit
import CloudKit
import IceCream
import RealmSwift

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // Keep both engines alive
    var privateEngine: SyncEngine!
    var sharedEngine: SyncEngine!

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Owner's engine (always needed)
        privateEngine = SyncEngine(
            objects: [SyncObject(type: Dog.self)],
            databaseScope: .private
        )

        // Participant's engine (needed if this user might receive shares)
        sharedEngine = SyncEngine(
            objects: [SyncObject(type: Dog.self)],
            databaseScope: .shared
        )
        return true
    }

    // Owner: called from a button, share sheet, etc.
    func shareAllDogs() {
        guard #available(iOS 15.0, *) else { return }
        privateEngine.createShare(type: Dog.self, publicPermission: .readOnly) { share, url, error in
            guard let url = url else { return }
            DispatchQueue.main.async {
                // Present UIActivityViewController with url, or send via Messages
            }
        }
    }

    // Participant: system callback when tapping the share link
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        sharedEngine.acceptShare(metadata: metadata) { error in
            print(error ?? "Shared records synced into Realm")
        }
    }

    // Both engines wake up on silent push automatically via the notification
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(
            name: Notifications.cloudKitDataDidChangeRemotely.name,
            object: nil
        )
        completionHandler(.newData)
    }
}
```

---

## Constraints and known limitations

| Item | Detail |
|---|---|
| **Minimum OS** | Zone-level sharing (`createShare`) requires iOS 15 / macOS 12. Participant sync works on any IceCream-supported OS. |
| **Zone granularity** | One share per record type (zone). You cannot share a subset of `Dog` records. |
| **Zone ID discovery** | Participant zones are discovered lazily on first `fetchChangesInDatabase`. Writes issued before discovery are silently dropped (correct behaviour — there is nothing to write to yet). |
| **Realm configuration** | Both engines default to `Realm.Configuration.defaultConfiguration`. If you use a custom configuration, pass it to `SyncObject(realmConfiguration:type:)`. Both engines should point at the same Realm file so shared and private records are queryable together. |
| **Revoking a share** | When the owner deletes the `CKShare`, IceCream receives a `recordZoneWithIDWasDeleted` callback, clears the zone token, and stops syncing that zone. Existing local records are not automatically deleted — implement that logic in your own `fetchChangesInDatabase` completion handler if needed. |
| **`UICloudSharingController`** | For per-participant invitations (instead of a public link), present `UICloudSharingController` using the `CKShare` returned by `createShare`. No changes to the IceCream setup are required. |
