# AngstromEngineering NuGet feed — auth via gh CLI (no PAT)

Reuse your existing GitHub login instead of creating/managing a classic PAT.
Your real GitHub identity becomes the credential, and `gh` OAuth tokens are stable.

Feed: `https://nuget.pkg.github.com/AngstromEngineering/index.json`
Org account: `sprokopowich` (work, not `sproko`)

## One-time setup per machine (global — covers every repo)

```bash
# 1. Add the read:packages scope to your existing gh login (interactive, opens browser)
gh auth refresh -h github.com -s read:packages

# 2. Wire the gh token into the user-level NuGet source
#    (creates/updates ~/.nuget/NuGet/NuGet.Config, perms 600)
dotnet nuget add source https://nuget.pkg.github.com/AngstromEngineering/index.json \
  --name Angstrom \
  --username sprokopowich \
  --password "$(gh auth token)" \
  --store-password-in-clear-text

#    If the source already exists, use `update` instead of `add`:
# dotnet nuget update source Angstrom \
#   --username sprokopowich --password "$(gh auth token)" --store-password-in-clear-text
```

## Verify

```bash
# Quick auth probe — expect 200
curl -s -o /dev/null -w "%{http_code}\n" \
  -u "sprokopowich:$(gh auth token)" \
  https://nuget.pkg.github.com/AngstromEngineering/index.json

# Real test
dotnet restore   # run from a repo that references AE packages
```

## Notes

- The token is **copied** into nuget.config as a snapshot. If you ever re-auth `gh`
  and the token rotates, just re-run step 2 (`update` form).
- Global setup means **no per-repo `nuget.config`**. A repo's tracked
  `.nuget/NuGet.Config` is NOT auto-read by `dotnet` — it only discovers files
  literally named `nuget.config` walking up the tree, never inside a `.nuget/`
  subfolder. Don't put credentials there (it's git-tracked anyway).

## Troubleshooting

| Error | Fix |
|---|---|
| `401 Unauthorized` | Token missing `read:packages` — re-run step 1, then step 2 |
| `403 Forbidden` | Wrong account — confirm `sprokopowich` is the org member |
| `Unable to load the service index` | Network/VPN issue reaching `nuget.pkg.github.com` |
