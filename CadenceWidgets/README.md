# CadenceWidgets — one manual Xcode step

The widget/Live Activity code is complete but lives in its own extension
target, which has to be created once in Xcode (targets can't be added safely by
editing the project file by hand).

## Add the extension target (~2 minutes)

1. **File → New → Target… → Widget Extension.**
   - Product name: `CadenceWidgets`
   - Uncheck "Include Configuration App Intent"; check **"Include Live Activity"** is *not* needed (our code already includes it).
   - Finish, and **Activate** the scheme when prompted.
2. Delete the template Swift files Xcode generated inside the new target's
   folder, then drag **`CadenceWidgets/CadenceWidgets.swift`** (this folder)
   into the target (target membership: *CadenceWidgets only*).
3. Give **`CadenceApp/Services/RestTimerActivity.swift`** dual target
   membership: select the file → File Inspector → check both **Cadence** and
   **CadenceWidgets**. (It defines `RestTimerAttributes`, shared by both.)
4. **App Groups** (lets the widget read today's score):
   - Cadence target → Signing & Capabilities → + Capability → App Groups →
     add `group.net.adnanahmad.Cadence`.
   - CadenceWidgets target → same capability, same group.
   - (The group ID is referenced in `WidgetBridge.swift` and
     `CadenceWidgets.swift`; change all three together if you rename it.)
5. The app's `Info.plist` already has `NSSupportsLiveActivities`. The widget
   extension needs no extra plist keys.

## What you get

- **Home Screen widget (small):** today's score in its verdict color, or the
  "Check in" prompt before the morning check-in. Refreshes when the app
  publishes (via `WidgetBridge`) and rolls over at midnight.
- **Rest-timer Live Activity:** Lock Screen + Dynamic Island countdown between
  sets, driven by `RestTimerActivityController` in the session player. Without
  the extension the in-app timer still works — the controller no-ops.
