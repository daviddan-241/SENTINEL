# Dev container

A browser tab is enough to build and test this repository's Swift core — no Mac, no Xcode.
The crypto, vault and chain code is a plain SwiftPM package, so it compiles anywhere Swift does.

1. Open the repository page → **Code → Codespaces → Create codespace on main**.
2. In the terminal it opens with:

```bash
cd ios
swift test                                   # 93 tests: BIP-39/32/44/49/84/86, vault, spam, decoders
swift run sentinel scan 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa      # a real, live scan
swift run sentinel prices                    # the USD rates portfolio totals use
```

Free personal accounts get 120 core-hours a month, which is about 60 hours on the 2-core machine
this container asks for. Delete the codespace when you are done and the clock stops.

The image is the official `swift:6.2-noble`, the same toolchain the `ios core` CI job installs,
so a green run here means the same thing a green run there does.

**What this does not give you:** Xcode. The SwiftUI app target in `SentinelWallet/` needs Apple's
SDK and a Mac to compile; that limitation is stated plainly in `ios/README.md` rather than hidden.
Everything underneath the app — including every cryptographic operation it performs — does build
and test here.
