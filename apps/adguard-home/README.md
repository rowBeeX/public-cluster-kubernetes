# AdGuard Home

DNS-Resolver mit Rewrite-Regeln für den Public-Cluster.

## Besonderheiten

- Läuft mit `hostNetwork: true` auf Port 53 (DNS) und 3000 (Web-UI)
- `pod-security.kubernetes.io/enforce: privileged` wegen hostNetwork
- NodeSelector: `public.sedware.net/control-plane: "true"` (nur Host-1)
- Bootstrap-Konfiguration kommt aus dem `adguard-config` Secret (SOPS)

## Speicher-Request: 1280Mi

Der Request folgt nicht dem Durchschnitt, sondern der Spitze. Gemessen über
14 Tage (Prometheus, `container_memory_working_set_bytes`): Ruhezustand rund
510 MiB, beim Neuladen der Filterlisten aber 1218 MiB und 1268 MiB — bei zwei
von fünf beobachteten Pod-Generationen. Sieben Listen, eine davon über zwei
Millionen Regeln.

Entscheidend ist nicht die Kapazität, sondern die OOM-Reihenfolge: der Kernel
wählt sein Opfer über `oom_score_adj = 1000 − 1000 · Request / Allocatable`.
Mit 64Mi stand AdGuard bei 989 und war damit der schlechteste Wert auf Host 1 —
ausgerechnet der DNS-Resolver jedes NetBird-Peers. Mit 1280Mi sind es 780, der
beste Wert des Nodes.

Rechnung für Host 1 (Stand 2026-08-12): allocatable 5829 MiB, angefordert
3832 MiB (65,7 %). Die Anhebung um 1216 MiB ergibt 5048 MiB (86,6 %); 781 MiB
bleiben unangefordert, die tatsächliche Belegung liegt bei 71 %. Auf Host 1
läuft per `nodeSelector` nichts, was zusätzlich dorthin geplant würde. Wer den
Wert senken will, senkt zuerst die Spitze — also Zahl und Größe der
Filterlisten, nicht den Request.

## Zugang

- Web-UI: `https://adguard.sedware.net` über den öffentlichen Envoy-Edge
  (Wildcard-TLS). Erreichbarkeit ist per `SecurityPolicy` auf die NetBird-Overlay-
  CIDR `100.64.0.0/10` beschränkt — Envoy weist jeden anderen Client ab, die UI
  ist also nie aus dem Internet erreichbar. Kein öffentlicher DNS-Eintrag; NetBird-
  Clients lösen `adguard.sedware.net` über AdGuard auf die Host-1-Overlay-IP
  auf und treffen dort den ko-lokalen Envoy.
- DNS: UDP/TCP 53 direkt auf Host-1 (hostNetwork). Die Host-Firewall gibt :53
  ausschließlich auf dem NetBird-Interface `nb-wt0` frei; auf allen anderen
  Interfaces wird der Port verworfen — kein offener öffentlicher Resolver
