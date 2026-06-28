# Authentik

OIDC-Provider für alle öffentlichen Cluster-Dienste.

## Komponenten

| Ressource | Beschreibung |
|-----------|-------------|
| PostgreSQL StatefulSet | Dedizierte Datenbank (local-path PVC) |
| Valkey Deployment | Redis-kompatibler Cache (kein nodeSelector — Achtung bei Node-Ausfall) |
| Authentik Server (2 Replicas) | HTTP-Server, OIDC-Endpunkte, Admin-UI |
| Authentik Worker (1 Replica) | Hintergrund-Tasks (E-Mail, Events) |
| authentik-media PVC | Medien-Speicher (public-shared-bulk, ReadWriteMany) |

## Secrets

Kommen aus SOPS via `public-cluster-nix/secrets/dev/public-cluster-host-1.yaml`:
- `authentik-runtime` — Datenbankpasswort, Secret-Key, SMTP-Konfiguration
- `authentik-blueprint` — Blueprint-YAML für initiale OIDC-Client-Konfiguration

## Zugang

- Admin-UI: `https://authentik.dev0.sedware.net/if/admin/` (nur über NetBird)
- OIDC-Issuer: `https://authentik.dev0.sedware.net/application/o/<client>/`
