# Authentik

OIDC-Provider für alle öffentlichen Cluster-Dienste, fest auf Version
`2026.5.4` gepinnt.

## Komponenten

| Ressource | Beschreibung |
|-----------|-------------|
| Externe PostgreSQL (`app-postgresql`, CNPG) | Datenbank im separaten App-Cluster `app-postgresql` (Host `postgres-rw.app-postgresql`, Passwort aus Vault) |
| Externer Valkey-Cache (`app-valkey`) | Redis-kompatibler Cache im separaten App `app-valkey` (`valkey.app-valkey`) |
| Authentik Server (1 Replica) | HTTP-Server, OIDC-Endpunkte, Admin-UI |
| Authentik Worker (1 Replica) | Hintergrund-Tasks (E-Mail, Events) |
| authentik-media PVC | Medien-Speicher (public-shared-bulk, ReadWriteMany) |

Der Cluster ist absichtlich vom Internet abgeschottet. Update-Prüfung,
Start-Analyse und Fehlerberichte sind deshalb auf Server und Worker
deaktiviert. Da ausschließlich OIDC-Provider verwendet werden, sind auch der
eingebettete Proxy-Outpost und die Kubernetes-Discovery abgeschaltet. So
entstehen in der Admin-Übersicht keine dauerhaften Internet- oder
Kubernetes-API-Retries.

## Secrets

Kommen aus SOPS via `public-cluster-nix/secrets/dev/public-cluster-host-1.yaml`:
- `authentik-runtime` — Secret-Key, SMTP-Konfiguration
- `authentik-blueprint` — Blueprint-YAML für initiale OIDC-Client-Konfiguration

Das Datenbankpasswort kommt aus Vault über den `authentik-db` VaultStaticSecret
(nicht aus `authentik-runtime`).

## Zugang

- Admin-UI: `https://authentik.dev9.sedware.net/if/admin/` — erreichbar über den
  öffentlichen Envoy-Edge (`public-dev`) per HTTPRoute; der Zugang wird durch
  Authentik-Login geschützt, nicht durch eine Netzwerk-/CNP-Beschränkung
- OIDC-Issuer: `https://authentik.dev9.sedware.net/application/o/<client>/`
