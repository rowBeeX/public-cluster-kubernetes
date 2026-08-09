# Mail Autoconfig

Statische Mozilla-/Thunderbird-Autoconfig-Datei, damit Mail-Clients (Nextcloud
Mail, Thunderbird, K-9, ...) beim Einrichten von `<name>@sedware.net` nur die
E-Mail-Adresse brauchen ("Auto Setup") statt Server/Port manuell einzutragen.

## Wie es funktioniert

Clients fragen beim Domain-Teil der E-Mail-Adresse nacheinander bekannte URLs
ab, u. a. `https://autoconfig.<domain>/mail/config-v1.1.xml`. Dieser Dienst
beantwortet genau diese Anfrage mit einer statischen XML-Datei, die auf den
echten Mailserver verweist:

```
IMAP:  stalwart.local.sedware.net:993 (SSL)
SMTP:  stalwart.local.sedware.net:465 (SSL)
```

Der Inhalt ist unkritisch (keine Secrets, vergleichbar mit öffentlich
sichtbaren MX/SPF-Records) — der eigentliche Mailserver bleibt weiterhin nur
über NetBird/LAN erreichbar, diese Datei ändert daran nichts.

## Zugang

- `https://autoconfig.sedware.net` über den öffentlichen Envoy-Edge
  (Wildcard-TLS, wie AdGuard). Kein öffentlicher Cloudflare-DNS-Eintrag —
  NetBird-Clients (und Pods im lokalen Cluster, deren DNS letztlich über
  denselben AdGuard-Pfad läuft) lösen `autoconfig.sedware.net` über AdGuards
  Wildcard-Rewrite `*.sedware.net` auf die Host-1-Overlay-IP auf.
- Erreichbarkeit ist per `SecurityPolicy` auf die NetBird-Overlay-CIDR
  `100.64.0.0/10` beschränkt (gleiches Muster wie bei AdGuard Home) — die
  Envoy-Edge-Listener sind sonst auch über die öffentliche IP erreichbar,
  auch ohne öffentlichen DNS-Eintrag.

## Betrieb

Ein einzelner `busybox httpd`-Container liefert die Datei aus einer
ConfigMap aus. Kein Egress nötig (reine statische Auslieferung); Ingress nur
vom Envoy-Edge (`host`/`remote-node`) auf Port 8080.

Um den Inhalt zu ändern (z. B. neuer Mailserver-Host/-Port), die ConfigMap in
`workload.yaml` anpassen und committen — kein Neustart des Pods nötig, sobald
Kubernetes die gemountete ConfigMap aktualisiert (kann laufzeitbedingt bis zu
einer Minute dauern).
