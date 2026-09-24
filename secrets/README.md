# Secrets (sops-nix + age)

Encrypted secrets are safe to commit; the age private keys are NOT.

## One-time
```bash
# 1. Your personal admin key (keep the private half safe, e.g. password manager):
age-keygen -o ~/.config/sops/age/keys.txt      # prints the public key -> .sops.yaml
# 2. After each host is installed, get its host key's age pubkey:
ssh z@<host> "sudo cat /var/lib/sops-nix/key.txt | age-keygen -y"
# 3. Paste all pubkeys into .sops.yaml, then:
cp secrets/secrets.yaml.example secrets/secrets.yaml
sops secrets/secrets.yaml       # fill in real values; saved encrypted
sops updatekeys secrets/secrets.yaml
```
The `.gitignore` blocks the plaintext example-filled files and any age key.
