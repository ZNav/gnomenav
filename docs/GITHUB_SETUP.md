# Create the private repo + PR the config

I can't push to your GitHub (no creds), so you run these. One-time:

```bash
# auth once:
gh auth login

# from the repo folder:
cd ~/nixos-homelab
git init -b main
# safety scan before first commit:
git add -A
git diff --cached --name-only | grep -iE 'key|secret' || echo "no obvious secret files staged"
git commit -m "chore: scaffold README + gitignore"    # keep first commit tiny

# create the PRIVATE repo and push main:
gh repo create nixos-homelab --private --source . --remote origin --push

# now do the real work on a branch and open a PR (your requested flow):
git checkout -b feat/initial-nixos-homelab
git add -A
git commit -m "feat: full NixOS flake — hosts, oci-containers, cloudflared, sops, data-safety"
git push -u origin feat/initial-nixos-homelab
gh pr create --fill --title "Initial NixOS homelab" \
  --body "Declarative NixOS for msi + x220. See docs/INSTALL_WALKTHROUGH.md. Merge after review."
```

## Verify no secrets committed (do this before merging)
```bash
git log -p | grep -iE 'BEGIN (RSA|OPENSSH) PRIVATE|age1[a-z0-9]{20,}|CLIENT_SECRET=[^x]' \
  && echo "!! secret found — scrub before merge" || echo "clean"
```
`secrets/secrets.yaml` is fine to commit ONLY after `sops` has encrypted it.
The `.sops.yaml` file holds public keys only — safe.
