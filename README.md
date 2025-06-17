# Static build test

```bash
# regular build
nix-build -j auto

# static build
nix-build --arg static true -j auto
```

