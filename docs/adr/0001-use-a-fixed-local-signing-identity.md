---
status: accepted
---

# Use a fixed local signing identity

Keyveer is a personal macOS utility whose active keyboard event tap and synthesized mouse events depend on TCC permissions surviving rebuilds. Local builds use the fixed bundle identifier `com.reinerlau.keyveer`, remain outside App Sandbox, and are signed with the fixed self-signed identity `Keyveer Local Development`; this avoids a paid Apple Developer membership while preserving a stable code identity on the author's Mac. A native spike on branch [`prototype/tcc-signing-spike`](https://github.com/ReinerLau/keyveer/tree/prototype/tcc-signing-spike) established that this fixed, self-signed identity pattern can retain Accessibility authorization across changed, re-signed builds.

## Consequences

- The signing certificate and private key stay in the author's login keychain and are never committed or exported with the repository.
- Keyveer deliberately establishes a fresh bundle identifier and certificate under the verified pattern; the first Keyveer launch therefore requires new TCC authorization.
- Losing, replacing, or allowing the certificate to expire changes the app's identity and is expected to require TCC authorization again.
- This identity is suitable only for local development and personal use; it cannot provide Gatekeeper-trusted distribution or notarization.
- If Keyveer is distributed later, it will move to Developer ID signing and should expect a one-time TCC reauthorization.
