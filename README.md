# nix-pangolin

NixOS flake and module for [Pangolin](https://github.com/fosrl/pangolin), a tunneled reverse proxy server with identity and access control (WebAuthn/Passkeys, OIDC, and per-resource policies).

## Why This Flake Exists

Upstream `nixpkgs` packaging for Pangolin has several critical runtime defects:
1. **Broken `.next` permissions**: The upstream wrapper copies `.next` from `/nix/store` with read-only permissions (`0555`), causing every subsequent restart to fail during Next.js cache cleanup with `Permission denied`.
2. **Missing database assets**: `server.mjs` synchronously reads `server/db/{names,ios_models,mac_models}.json`. Upstream installs them into `dist/` but never into `server/db/`.
3. **Broken systemd hardening**: Upstream sets `SocketBindDeny=ipv4:tcp`, which prevents the Node/Next process from binding internal and external TCP listening ports on localhost.
4. **Missing CLI**: The `pangctl` management CLI is built but never exposed in `$out/bin`.
5. **Port conflicts**: Defaults `internal_port` to `3001`, colliding with Grafana and common monitoring tools.

`nix-pangolin` resolves all of these issues out of the box.

## Features

- **Robust Wrapper**: Handles `.next` directory write permissions and database assets reliably across restarts.
- **`pangctl` CLI**: Exposes the CLI for administrative operations (admin account seeding, secret rotation, passkey resets).
- **Declarative Initial Admin**: Seed an admin account (`initialAdmin.email` and `passwordFile`) directly in NixOS without clicking through the setup wizard.
- **Declarative Secrets**: Auto-generates and persists `SERVER_SECRET` or accepts an agenix secret file.
- **Port Conflict Protection**: Defaults `internal_port` to `3005` (avoiding the common port 3001 collision with Grafana).
- **Caddy Integration**: Simple toggle `services.pangolin.caddy.enable = true` to reverse-proxy through Caddy.

## Quick Start

### 1. Add Flake Input

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-pangolin.url = "github:deepwatrcreatur/nix-pangolin";
  };

  outputs = { self, nixpkgs, nix-pangolin, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-pangolin.nixosModules.default
        {
          services.pangolin = {
            enable = true;
            baseDomain = "example.com";
            dashboardDomain = "pangolin.example.com";

            # Optional: Declarative admin seeding (bypasses setup token wizard)
            initialAdmin = {
              enable = true;
              email = "admin@example.com";
              passwordFile = "/run/secrets/pangolin-admin-password";
            };

            # Optional: Caddy ingress
            caddy.enable = true;
          };
        }
      ];
    };
  };
}
```

### 2. Manual CLI Management

Run the Pangolin management CLI directly:

```bash
nix run github:deepwatrcreatur/nix-pangolin#pangctl -- --help
```

Or on an installed system:

```bash
pangctl set-admin-credentials --email admin@example.com --password <secret>
```

## License

AGPL-3.0 (same as upstream Pangolin).
