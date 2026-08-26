---
status: accepted
---

# Use a fixed local signing identity

Mouseless is a personal macOS utility whose active keyboard event tap and synthesized mouse events depend on TCC permissions surviving rebuilds. Local builds use the fixed bundle identifier `com.reinerlau.mouseless`, remain outside App Sandbox, and are signed with the fixed self-signed identity `Mouseless Local Development`; this avoids a paid Apple Developer membership while preserving a stable code identity on the author's Mac. A native spike on branch [`prototype/tcc-signing-spike`](https://github.com/ReinerLau/mouseless/tree/prototype/tcc-signing-spike) verified that changed, re-signed bundle contents retained Accessibility/Input Monitoring authorization and continued to filter keyboard input and post pointer movement.

## Consequences

- The signing certificate and private key stay in the author's login keychain and are never committed or exported with the repository.
- Losing, replacing, or allowing the certificate to expire changes the app's identity and is expected to require TCC authorization again.
- This identity is suitable only for local development and personal use; it cannot provide Gatekeeper-trusted distribution or notarization.
- If Mouseless is distributed later, it will move to Developer ID signing and should expect a one-time TCC reauthorization.
