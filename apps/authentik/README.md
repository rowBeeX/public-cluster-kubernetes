# Authentik

OIDC-Provider für alle öffentlichen Cluster-Dienste, fest auf Version
`2026.8.0` gepinnt.

## Komponenten

| Ressource | Beschreibung |
|-----------|-------------|
| Externe PostgreSQL (`app-postgresql`, CNPG) | Datenbank im separaten App-Cluster `app-postgresql` (Host `postgres-rw.app-postgresql`, Passwort aus Vault); trägt seit 2026.5 auch Cache und Channel-Layer |
| Authentik Server (1 Replica) | HTTP-Server, OIDC-Endpunkte, Admin-UI |
| Authentik Worker (1 Replica) | Hintergrund-Tasks (E-Mail, Events) |
| authentik-media PVC | Medien-Speicher (public-shared-bulk, ReadWriteMany) |

## Der Sprung auf 2026.8.0 und warum es keinen Rückweg gibt

`2026.5.6` → `2026.8.0` ist ein direkter Schritt: Trains `2026.6`/`2026.7`
existieren nicht, `2026.5.6` ist die höchste `2026.5.x`. Die in 2026.8 neu
eingebaute Lifecycle-Prüfung (`lifecycle/migrate.py`,
`ensure_allowed_version`) lässt genau die eigene und die vorherige
Version-Familie zu, und `authentik/__init__.py` des Zielimages setzt
`VERSION_FAMILY_PREVIOUS = "2026.5"` — der Schritt ist also nicht nur
inoffiziell möglich, sondern vom Zielcode ausdrücklich erlaubt.

**Ein Image-Rollback ist danach kein Rückweg mehr.** Die Django-Migrationen
laufen nur vorwärts; `kubectl rollout undo` holt das Pod-Template zurück, nicht
das Schema, und alter Code trifft dann auf ein neueres Schema. Der einzige
belastbare Rückweg ist ein CNPG-PITR der Datenbank `authentik` auf einen
Zeitpunkt vor dem Image-Wechsel — deshalb gehört unmittelbar davor ein
On-Demand-Base-Backup mit notiertem `stoppedAt`.

Was sich fachlich ändert:

- **`AUTHENTIK_WEB__BASE_URL` ist jetzt gesetzt** (beide Deployments). Ab
  2026.11 ist die Einstellung Pflicht; sie hier vorzuziehen kostet nichts und
  erspart den Zwang beim nächsten Sprung.
- **Sessions werden bei Deaktivierung eines Nutzers gelöscht**, und
  OAuth2-Provider schicken dabei ein Back-Channel-Logout. Ein deaktivierter
  Nutzer verliert damit seinen Zugang zu allen zehn Applications sofort statt
  erst mit Ablauf des Tokens — Absicht, aber eine Verhaltensänderung.
- **`hash_password` nimmt das Passwort nicht mehr als Positionsargument.**
  Hier ohne Wirkung: kein Manifest und kein Skript dieses Repos ruft es auf.
- **`AUTHENTIK_POSTGRESQL__CONN_OPTIONS` ist deprecated.** Wird hier nicht
  gesetzt — nichts zu tun, aber nicht neu einführen.
- **WebAuthn-Option „Prevent duplicate devices" entfällt.** Im Blueprint
  (`public-cluster-nix`) nicht gesetzt, also ohne Wirkung.

Beide Deployments laufen wegen der `podAntiAffinity` gegen `postgres` auf
`public-cluster-host-2`, also **aarch64**. Der gepinnte Digest muss deshalb der
Multi-Arch-Index sein; für `2026.8.0` enthält er `linux/amd64` und
`linux/arm64`.

## Kein Redis/Valkey

Authentik 2026.5 hat Redis vollständig abgelegt: `authentik/root/settings.py`
setzt `CACHES["default"]` auf `django_postgres_cache.backend.DatabaseCache` und
`CHANNEL_LAYERS` auf `django_channels_postgres`; im gesamten Paket kommt die
Zeichenkette `redis` nicht mehr vor. `AUTHENTIK_REDIS__*` wird vom Config-Loader
zwar noch in `ak dump_config` gespiegelt, aber von nichts gelesen — die Angabe
sah nach Konfiguration aus und war keine. Nachgewiesen am laufenden Pod: genau
eine etablierte TCP-Verbindung, die nach Postgres:5432.

Der Signierschlüssel profitiert davon ohnehin nicht: `CertificateKeyPair.
private_key` in `authentik/crypto/models.py` cacht das geparste PEM nur auf der
Modellinstanz (`self._private_key`), nie im Django-Cache. Er wird deshalb pro
Anfrage neu geparst, unabhängig vom Cache-Backend.

Deshalb signieren alle zehn Provider mit einem eigenen **RSA-2048**-Schlüssel
(`sedware-oidc-signing`) statt mit dem RSA-4096-Schlüssel, den Authentik sich
beim ersten Start selbst anlegt: auf aarch64 kostet `load_pem_private_key`
1279 ms bei 4096 Bit und 177 ms bei 2048 Bit. `alg` bleibt RS256, es schrumpft
nur der Modulus. Deklariert ist der Schlüssel im Blueprint in
`public-cluster-nix`; der auto-generierte Schlüssel bleibt unreferenziert
bestehen.

Die Pods haben per CiliumNetworkPolicy keinen Internet-Egress — erlaubt sind nur
DNS und PostgreSQL. Update-Prüfung, Start-Analyse und Fehlerberichte sind
deshalb auf Server und Worker deaktiviert. Da ausschließlich OIDC-Provider verwendet werden, sind auch der
eingebettete Proxy-Outpost und die Kubernetes-Discovery abgeschaltet. So
entstehen in der Admin-Übersicht keine dauerhaften Internet- oder
Kubernetes-API-Retries.

## Platzierung: weg vom Datenbank-Knoten

Server und Worker meiden per `podAntiAffinity` den Node, auf dem der
CNPG-Pod `postgres` läuft. Die frühere Bindung an den Control-Plane-Node
belastete host-1 mit allem, was nicht durch ein Volume dort festgenagelt ist:
gemessen am 2026-08-11 stand host-1 bei 4013 MiB / 1309m CPU gegen 2696 MiB /
512m auf host-2, bei praktisch gleichen Requests — allein durch die
Platzierung. Authentik ist frei verschiebbar, weil sein einziges Volume
`authentik-media` als ReadWriteMany auf der SMB-Storage-Box liegt, nicht
knotenlokal; der Preis dafür sind gemessene 3,3 ms RTT je
Datenbank-Roundtrip über das private Hetzner-Netz (`10.10.0.0/24`) statt
eines Loopbacks.

## Secrets

Kommen aus SOPS via `public-cluster-nix/secrets/public-cluster-host-1.yaml`:
- `authentik-runtime` — Secret-Key und Bootstrap-Zugangsdaten (`akadmin`)
- `authentik-blueprint` — Blueprint-YAML für initiale OIDC-Client-Konfiguration,
  dazu `signing-key.pem` und `signing-cert.pem`. Beide Pods mounten das Secret
  nach `/blueprints/custom`; das Blueprint liest die PEMs von dort per `!File`,
  weil `envsubst` mehrzeilige Werte nicht eingerückt einsetzen kann. Die
  Blueprint-Suche greift nur `**/*.yaml` ab, die PEMs stören sie nicht.

Das Datenbankpasswort kommt aus Vault über den `authentik-db` VaultStaticSecret
(nicht aus `authentik-runtime`).

## Zugang

- Admin-UI: `https://authentik.sedware.net/if/admin/` — erreichbar über den
  öffentlichen Envoy-Edge (`public`) per HTTPRoute; der Zugang wird durch
  Authentik-Login geschützt, nicht durch eine Netzwerk-/CNP-Beschränkung
- OIDC-Issuer: `https://authentik.sedware.net/application/o/<client>/`
