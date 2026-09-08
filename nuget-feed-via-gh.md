# AngstromEngineering NuGet feed — auth via gh CLI (no PAT)

Reuse your existing GitHub login instead of creating/managing a classic PAT.
Your real GitHub identity becomes the credential, and `gh` OAuth tokens are stable.

Feed: `https://nuget.pkg.github.com/AngstromEngineering/index.json`
Org account: `sprokopowich` (work, not `sproko`)

> **Which account `gh` answers as depends on the directory.** direnv exports a
> per-directory `GH_CONFIG_DIR`, so `gh auth token` returns the **personal**
> (`sproko`) token anywhere outside `~/aerepo`. Run these from `~/aerepo`, or set
> `GH_CONFIG_DIR` explicitly as below. Get this wrong and the personal token is
> wired into the work feed — which still returns 200 on the service index, so it
> looks fine until a restore 401s.

## One-time setup per machine (global — covers every repo)

```bash
# GH_CONFIG_DIR is spelled out rather than relying on being cd'd into ~/aerepo,
# because these get pasted into whatever shell is to hand.
export GH_CONFIG_DIR="$HOME/.config/gh-work"

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
# Confirms read:packages is actually on the token. The service index alone does
# NOT — GitHub serves it to any valid token, including one with no package
# scope and the personal account's token, so a 200 there proves nothing.
GH_CONFIG_DIR="$HOME/.config/gh-work" \
  gh api "/orgs/AngstromEngineering/packages?package_type=nuget&per_page=5" \
  --jq '.[].name'

# Real test, from a throwaway project so it works on a machine with no AE repo
# cloned yet. Substitute any package name from the list above.
dotnet new classlib -o /tmp/nugetprobe --no-restore
(cd /tmp/nugetprobe && dotnet add package AE.Logger) && rm -rf /tmp/nugetprobe
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
| `401` but `curl` on the index returns 200 | The personal token got wired in: step 2 ran without `GH_CONFIG_DIR`. Re-run it with the export set |
| `403 Forbidden` | Wrong account — confirm `sprokopowich` is the org member |
| `Unable to load the service index` | Network/VPN issue reaching `nuget.pkg.github.com` |
| Worked yesterday, 401s today | `gh` re-auth rotated the token; the one in nuget.config is a snapshot. Re-run step 2 in `update` form |
| Rider 401s while the CLI works | Rider caches sources at startup — restart it after step 2 |
