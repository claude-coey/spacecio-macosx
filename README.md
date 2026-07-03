# SpaceSIO Relay (macOS)

A native macOS relay station for the SpaceSIO broadcast network. Enter a
radio-feed API key and the app:

1. **Pulls** the next queued signal from the radio feed API (`/api/radio/next`).
2. **Broadcasts** the proof packet over your WiFi radio — the bytes are sent as
   UDP broadcast datagrams (port `47727`) on your local network, physically
   leaving the Mac's WiFi radio as RF. Optionally sonified as an audible chirp.
3. **Confirms** with a signed receipt (`/api/radio/complete`): an Ed25519
   signature over `{id, payload hash, timestamp, lat, lon}` plus the station's
   public key and location. The server verifies the signature and responds with
   the permalink + Certificate of Issuance URL, shown in the app.

Together, many relay stations form a distributed network of broadcasters.

## Requirements

- macOS 13+
- Apple Command Line Tools (`xcode-select --install`) **or** Xcode

## Run

```sh
cd spacecio-macosx
swift run
```

Or open the `macos-relay` folder in Xcode and press Run.

## Setup

- **API key** — create one in the operator console at **Admin → Radio API**
  (requires migration `0016`; the legacy `RADIO_FEED_TOKEN` also works).
- **Location** — the app asks CoreLocation once when going on air. macOS can be
  stingy granting location to terminal-run builds, so Settings offers manual
  coordinates as a fallback. Location is optional; confirmations are still
  signed without it.
- **Station identity** — an Ed25519 keypair is generated on first run and kept
  in your Keychain. The public key identifies your station on every
  confirmation.
- **Chirp** — toggle the audible packet sonification in Settings.

## Signed confirmation format

The exact string signed (and verified server-side, migration `0017`):

```
spacesio-confirm-v1
id:<transmission id>
hash:<payload_hash>
at:<ISO8601 UTC>
lat:<decimal degrees, 5 dp, or empty>
lon:<decimal degrees, 5 dp, or empty>
```

Sent as `{ signed_payload, signature, pubkey }` (base64 raw Ed25519) in the
`POST /api/radio/complete` body.
