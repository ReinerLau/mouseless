---
status: accepted
---

# Adopt Keyveer and retire the legacy project identity

The project adopts **Keyveer** as its sole public and internal product name to avoid conflicting with the installed reference application from Sonuscape LLC. The current checkout, source paths, modules, bundle identifiers, signing identity, documentation, generated products, repository remote, and local workspace use Keyveer; retaining Git history is the only deliberate exception, and the project accepts a one-time TCC reauthorization in exchange for a clean identity boundary.

## Consequences

- Existing configuration is validated and copied once, outside the application, to `~/Library/Application Support/Keyveer/config.json`; Keyveer contains no runtime compatibility path for the legacy location.
- The reference application and its files are external to this project and remain untouched.
- A repository guard rejects the retired brand in current paths or contents. Historical commits are preserved rather than rewritten.
- The GitHub repository and local workspace directory use `keyveer`; an external redirect retained by the hosting service is outside the project boundary.
