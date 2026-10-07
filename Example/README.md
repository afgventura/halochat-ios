# HaloChat iOS sample

A minimal UIKit app that opens the HaloChat UI kit's drop-in chat screen
(`HaloChatWidget` → `initiateChat()` → `startChat`), plus a SwiftUI sheet variant (`HaloChatView`).

1. Get your channel's **server key** (`hck_…`) from the HaloAI dashboard
   (Integrations → your Mobile App channel → HaloChat).
2. Start the stand-in backend (it plays the part of your server):
   `HALOCHAT_SERVER_KEY=hck_… node backend/server.mjs`
3. `brew install xcodegen && xcodegen generate`, open `HaloChatSample.xcodeproj`, run on a simulator.
4. Tap **Chat with CS**.

The app never holds the server key: it asks the backend for a short-lived `hct_` token,
exactly as your app will ask your backend after your own login.

Without the backend the chat still opens and shows the empty state with a "Reconnecting…" banner.
Launch with `-autoOpenChat YES` to open the chat straight away (used for screenshots).
