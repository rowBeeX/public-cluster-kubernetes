# mail-wellknown — Autoconfig-Fallback am Apex

Liefert genau eine Datei:
`https://sedware.net/.well-known/autoconfig/mail/config-v1.1.xml`.

Ein `busybox httpd` mit der XML aus einer ConfigMap, mehr nicht — kein Egress,
kein Zustand, kein ServiceAccount-Token.

## Warum es diese App gibt

Mail-Clients fragen die Mozilla-Autoconfig nacheinander an mehreren Orten ab.
Die eigentliche Antwort unter `autoconfig.sedware.net` liegt im **lokalen**
Cluster (`local-cluster-kubernetes/apps/mail-autoconfig`); der
`.well-known`-Pfad hängt dagegen an der nackten Domain `sedware.net`, und die
wird ausschließlich über den Public-Edge geroutet.

Ohne eigene Antwort hier fällt die Anfrage auf den pfadlosen Catch-all
`apex-to-authentik` (public-cluster-nix) zurück und liefert HTML statt XML.
Das ist mehr als kosmetisch: ältere Thunderbird-/Betterbird-Versionen
(`PriorityOrderAbortable`-Codepfad, vor der `promiseFirstSuccessful`-Umstellung
in comm-central) parsen den Body dieser Priority-Gruppe unabhängig davon, dass
die `autoconfig.<domain>`-Antwort bereits erfolgreich war, und werfen an der
unparsbaren HTML-Seite eine Exception, die den **gesamten** Abruf abbricht.
Derselbe Bug betrifft `autodiscover.sedware.net`.

## Exposition

- Nur der `apex-https`-Listener. Am `apex-http`-Listener wäre die XML im
  Klartext abrufbar; sie nennt die Hostnamen und den Auth-Mechanismus, denen
  ein Mail-Client vertrauen soll, und ist über HTTP manipulierbar. Port 80 am
  Apex bedient der HTTP->HTTPS-Redirect in `public-cluster-nix`.
- Bewusst **ohne** NetBird-Beschränkung öffentlich: der Inhalt ist so
  öffentlich wie die MX-/SPF-Records, und reale ISPs (GMX, Web.de, T-Online)
  halten ihren `.well-known`-Fallback genauso. Der Mailserver selbst bleibt
  NetBird/LAN-only.
- `path: Exact` statt `PathPrefix`: höchste Gateway-API-Präzedenz, schlägt den
  Catch-all und deckt genau diese eine Datei ab.

## Synchronität

Der XML-Inhalt MUSS mit
`local-cluster-kubernetes/apps/mail-autoconfig/mail-autoconfig-config/config-v1.1.xml`
übereinstimmen; `cluster-tools/lib/checks/mail_autoconfig_kopie.py` prüft die
Gleichheit. Zwei Antworten mit unterschiedlichen Ports oder Hostnamen ergeben
ein Mail-Konto, das je nach Abrufreihenfolge anders konfiguriert wird.
