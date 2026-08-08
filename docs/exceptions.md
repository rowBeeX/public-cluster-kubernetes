# Security- und Betriebs-Ausnahmen — public-cluster-kubernetes

Zentrale, überprüfbare Liste bewusster Abweichungen vom gehärteten Standard
(Baseline PSS, Least-Privilege, Restricted Trust, GitOps-deklarativ). Jede
Ausnahme hat eine ID, einen Owner (Team/Rolle, keine Person), eine Begründung,
das Restrisiko und ein Review-Datum.

> Diese Datei ist auf `public-cluster-kubernetes` begrenzt. Eine
> repoübergreifende Konsolidierung wird in Issue #35 verfolgt.

| ID | Owner | Begründung | Risiko | Review |
|----|-------|--------|------|--------|
| `EXC-mailedge-baseline-psa` | platform-mail | Der Postfix-Master benötigt UID 0 (privilege-separated Design) → Namespace `app-mailedge` erzwingt **baseline**, nicht restricted. Die Capabilities sind so weit wie möglich Richtung restricted minimiert (#11): `drop:[ALL]` + nur `CHOWN,DAC_OVERRIDE,FOWNER,SETGID,SETUID,NET_BIND_SERVICE,KILL,SYS_CHROOT` ergänzt; seccomp RuntimeDefault; `allowPrivilegeEscalation:false`. | Der Container läuft als root; eine Postfix-RCE hätte root im Container, aber nur die 8 gelisteten Caps (kein NET_RAW/MKNOD/AUDIT_WRITE/SETFCAP/SETPCAP/FSETID), keine Host-Namespaces. | 2026-10-01 |
| `EXC-postfix-writable-rootfs` | platform-mail | `readOnlyRootFilesystem:true` ist für `mail-edge/postfix` nicht erreichbar (#11/#12): das `boky/postfix`-Image erzeugt `/etc/postfix` bei jedem Start neu, und Postfix schreibt `/var/lib/postfix/prng_exch`. Mit derselben Begründung in der Conftest-`_rootfs_exceptions`-Allowlist geführt. | Beschreibbarer Image-Layer im Container; der Queue-Zustand liegt je Pod auf einer eigenen PVC aus den `volumeClaimTemplates` des StatefulSets (`spool-mail-edge-0` und `spool-mail-edge-1`), TLS ist ein read-only Mount. | 2026-10-01 |
| `EXC-adguard-privileged-psa` | platform-net | `app-adguard-home` erzwingt **privileged** PSA, weil AdGuard mit `hostNetwork:true` läuft, um Host-`:53`/`:3000` zu binden (DNS + UI über NetBird). Der Container selbst ist gehärtet (drop ALL, nur NET_BIND_SERVICE, read-only root fs). | Teilt sich den Host-Netzwerk-Namespace auf Host 1; `:53` ist per Firewall auf das NetBird-Overlay-Interface `nb-wt0` begrenzt (AR-05), nicht auf das öffentliche Internet. | 2026-10-01 |
| `EXC-authentik-baseline-psa` | platform-iam | `app-authentik` erzwingt **baseline**: Das Authentik-Image benötigt ein beschreibbares Root-Dateisystem (Blueprints/Medien/Cache unterhalb des Image-Root), restricted ist damit nicht erreichbar. Die Caps sind auf ALL reduziert. | Beschreibbarer Image-Layer; keine zusätzlichen Caps, keine Host-Namespaces, nicht privilegiert. | 2026-10-01 |
| `EXC-netbird-baseline-psa` | platform-net | `app-netbird` erzwingt **baseline**: Der netbird-dashboard-nginx-Container ergänzt `CHOWN,SETUID,SETGID` (zum Privilege-Drop von root) und `DAC_OVERRIDE` (Logdateizugriff) über das bei restricted erlaubte NET_BIND_SERVICE hinaus. | Zusätzliche Caps auf die gelistete Menge begrenzt; sonst drop ALL, nicht privilegiert, keine Host-Namespaces. | 2026-10-01 |
