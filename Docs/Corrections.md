# Corrections apportées (octobre 2026)

Ce document liste ce qui a été corrigé dans la configuration d'origine (`globals.yml`, inventaire, scripts, README), pourquoi, et ce qui reste à vérifier. La section 1 vient d'une **analyse statique** ; la section 4 reprend les constats du lab réel (08/10/2026) : `bootstrap-servers` et `pull` ont été exécutés, mais ni `prechecks` ni `deploy`. La validation finale reste celle de `kolla-ansible prechecks` puis `deploy`.

## 1. Corrections

| # | Problème d'origine | Correction | Source |
|---|--------------------|------------|--------|
| 1 | OpenStack **2024.2** est en fin de vie (29/04/2026) et ne supporte que Rocky Linux 9, alors que les VMs sont en Rocky 10.2 | Cible **2026.1 (Gazpacho)**, série SLURP maintenue | [Séries](https://releases.openstack.org/), [matrice 2024.2](https://docs.openstack.org/kolla-ansible/2024.2/user/support-matrix.html), [notes 2025.1](https://docs.openstack.org/releasenotes/kolla-ansible/2025.1.html) (Rocky 10 ajouté en 20.4.0) |
| 2 | `pip install kolla-ansible` sans version : installe une série qui peut différer de `openstack_release` | `pip install git+https://opendev.org/openstack/kolla-ansible@stable/2026.1` ; `ansible-core` 2.19 à 2.20 | [Quickstart 2026.1](https://docs.openstack.org/kolla-ansible/2026.1/user/quickstart.html), [notes 2026.1](https://docs.openstack.org/releasenotes/kolla-ansible/2026.1.html) |
| 3 | `docker_registry: docker.io` / `docker_namespace: kolla` | Surcharges retirées : le défaut de la release est `quay.io/openstack.kolla` | [Commit « Switch default images source to quay.io »](https://gitea09.opendev.org:3081/openstack/kolla-ansible/commit/0d9477de3899886165eae2b3a06ef316bebf59d8) |
| 4 | **Zun** et **Kuryr** activés (`enable_zun`, `enable_kuryr`, `enable_horizon_zun`, `docker_configure_for_zun`, `containerd_configure_for_zun`) | Retirés : supprimés de Kolla-Ansible en 2026.1 | [Notes 2026.1](https://docs.openstack.org/releasenotes/kolla-ansible/2026.1.html) |
| 5 | TLS interne **et** externe activés avec une VIP unique | Seul `kolla_enable_tls_internal` : la documentation indique que, sur un seul réseau, le TLS ne s'active que via les variables internes | [Guide TLS](https://docs.openstack.org/kolla-ansible/2026.1/admin/tls.html) |
| 6 | CA privée sans `openstack_cacert` ni `kolla_admin_openrc_cacert` | Ajoutés (`/etc/pki/tls/certs/ca-bundle.crt` pour Rocky ; CA dans `/etc/kolla/certificates/ca/root.crt`) | [Guide TLS](https://docs.openstack.org/kolla-ansible/2026.1/admin/tls.html) |
| 7 | `kolla_verify_tls_backend: yes` sans `kolla_enable_tls_backend` | Retiré (sans objet tant que le TLS backend n'est pas activé) ; les deux sont proposés en commentaire comme durcissement ultérieur | [Guide TLS](https://docs.openstack.org/kolla-ansible/2026.1/admin/tls.html) |
| 8 | `cinder_enabled_backends: "lvm"` | Retiré : absent de la documentation ; Kolla calcule normalement la liste des backends à partir de `enable_cinder_backend_lvm` (une chaîne `"lvm"` imposée à la main risque de casser ce calcul) | [Guide Cinder](https://docs.openstack.org/kolla-ansible/2026.1/reference/storage/cinder-guide.html) |
| 9 | Octavia : `octavia_amp_flavor_id: "auto"`, `octavia_amp_image_tag: "current"`, `octavia_amp_network`/`subnet` en chaînes, `octavia_amp_boot_network_list` avec un CIDR | Octavia passe en phase 2 ; bloc corrigé en commentaire (flavor et réseau sont des dictionnaires, la liste de réseaux attend un ID, étiquette `amphora`, image à construire) | [Guide Octavia](https://docs.openstack.org/kolla-ansible/2026.1/reference/networking/octavia.html) |
| 10 | Commentaire « Valkey obligatoire pour Octavia en 2024.2 » | Faux : Valkey n'existe qu'à partir de la série 2025.x ; en 2026.1 il sert de cache de sessions à Horizon | [Notes 2025.1](https://docs.openstack.org/releasenotes/kolla-ansible/2025.1.html), [notes 2026.1](https://docs.openstack.org/releasenotes/kolla-ansible/2026.1.html) |
| 11 | Ceilometer + Aodh + Gnocchi avec `gnocchi_backend_storage: file` sur 3 contrôleurs (métriques incohérentes, signalé dans vos propres commentaires) | Passés en phase 2, avec backend partagé requis | commentaire d'origine |
| 12 | Commentaire « Sauvegarde des volumes — désactivée » alors que `enable_cinder_backup: "yes"` | Commentaire corrigé | — |
| 13 | Inventaire : copie complète mélangeant des groupes de plusieurs séries (`neutron-ovn-vpn-agent`, `prometheus-valkey-exporter`…, ajoutés à la main sous l'intitulé « Dalmatian ») | `Config/multinode.hosts` (vos hôtes) + `Scripts/build-inventory.sh` qui reprend l'inventaire livré avec la version installée ; `[loadbalancer]` explicitement sur les 3 contrôleurs | [Notes 2026.1](https://docs.openstack.org/releasenotes/kolla-ansible/2026.1.html) (les groupes Cinder ont changé) |
| 14 | `Swift/build_swift_rings.sh` : image `kolla/rocky-source-swift-base:2024.2` (ancien schéma de nommage), jamais mentionné dans le README, écrasait les anneaux existants | Image configurable, refus d'écraser sans `FORCE=1`. **Corrigé ensuite** : l'image par défaut n'existe pas, Swift est désactivé et le script exige désormais `KOLLA_SWIFT_BASE_IMAGE` (voir section 4) | [Guide Swift](https://docs.openstack.org/kolla-ansible/2024.2/reference/storage/swift-guide.html) |
| 15 | README : chemins `/usr/local/share/kolla-ansible/...` (sans l'environnement virtuel), VIP `.10` et `openstack.local` alors que `globals.yml` utilise `.14` et `openstack.tubie.lan`, `[deployment] controller01` alors que l'inventaire utilise `localhost`, Horizon en `http://`, contraintes `2024.2`, 10 captures inexistantes (`Pic-29` à `Pic-38`) | Corrigés ; captures laissées en commentaire HTML jusqu'à leur ajout | — |
| 16 | Clonage de VM sans régénération du `machine-id` ni des clés SSH | Étape ajoutée en 4.2 (recommandation générale, non issue de la documentation Kolla) | — |

## 2. Changements de périmètre à connaître

- **Octavia**, **Ceilometer**, **Aodh** et **Gnocchi** passent de « activés » à « phase 2 » : ils ne pouvaient pas fonctionner correctement tels que configurés. Les blocs sont prêts à décommenter dans `globals.yml`.
- **`Config/multinode`** (copie complète de l'inventaire) est supprimé ; il reste dans l'historique git.

## 3. Points non vérifiés

Les sources officielles de certains fichiers (`all.yml`, inventaire livré) étaient inaccessibles depuis l'environnement d'analyse. À contrôler à l'exécution :

- Docker : le pin `3:28.*` n'a eu aucun effet et Docker 29.8.2 a été installé ; `bootstrap-servers` et `pull` ont réussi, mais le `deploy` n'a pas encore été exécuté avec cette version.
- Swift : tranché, les images n'existent pas pour 2026.1 (section 4). À revoir si une série ultérieure les publie à nouveau.
- Rocky Linux 10 avec 2026.1 : `bootstrap-servers` a réussi sur les 6 nœuds et les images `2026.1-rocky-10` existent ; `prechecks` et `deploy` restent à exécuter.
- `enable_neutron_agent_ha` : cité dans les notes de version, non testé.
- Variables conservées sans vérification : `workaround_ansible_issue_8743`, `enable_etcd`, `enable_valkey`.
- Le marqueur `[baremetal:children]` utilisé par `build-inventory.sh` pour couper l'inventaire livré : présent dans l'inventaire d'origine, à confirmer sur celui de 2026.1 (le script s'arrête avec un message clair s'il est absent).

Commandes de contrôle conseillées sur `controller01` :

```bash
ansible-inventory -i ~/multinode --graph | head -50
kolla-ansible prechecks -i ~/multinode
```

## 4. Constats du lab (08/10/2026)

| # | Constat | Action | Détail |
|---|---------|--------|--------|
| 17 | Aucune image Swift pour 2026.1 sur quay.io (seule `2024.2-rocky-9` existe pour `swift-base` et `swift-proxy-server`), alors que `nova-api` et `keystone` existent en `2026.1-rocky-10` | `enable_swift: "no"` ; `build_swift_rings.sh` n'a plus d'image par défaut ; étape des anneaux retirée du README ; disques Swift non requis | [Dépannage](Depannage.md#image-introuvable--manifest-unknown) |
| 18 | La sauvegarde Cinder utilisait Swift comme destination | `enable_cinder_backup: "no"`, driver commenté ; à remettre avec NFS, Ceph ou S3 | `globals.yml` |
| 19 | `docker_yum_package_pin: "3:28.*"` sans effet : Docker 29.8.2 installé | Pin retiré, commentaire explicatif | [Dépannage](Depannage.md#version-de-docker) |
| 20 | **Erreur de ma part** : le tableau du README donnait `storage01` en `172.20.10.8`, adresse réelle de `compute01` ; la ligne `fstab` NFS reprenait cette IP | Tableau, `/etc/hosts` et `fstab` corrigés avec les IP mesurées (`.3`, `.6`, `.7`, `.8`, `.9`, `.10`) ; explication de la ligne `fstab` et contrôle `showmount` ajoutés | [Dépannage](Depannage.md#montage-nfs-glance) |
| 21 | VMs sous-dimensionnées : contrôleurs 3,8 Go, autres nœuds 1,9 Go (plan : 24 et 16 Go) | Tableau avec valeurs mesurées et recommandées ; avertissement avant `deploy` | [Dépannage](Depannage.md#ram-insuffisante) |
| 22 | **Erreur de ma part** : le contrôle d'inventaire attendait `cinder-volume` sur `storage01`. Avec 2026.1, c'est le groupe `cinder-volume-lvm` qui y est rattaché | Contrôle corrigé dans le README ; vérification `openstack volume service list` ajoutée | [Dépannage](Depannage.md#cinder--groupes-et-contrôle) |
| 23 | La plage d'adresses flottantes proposée (`.9` à `.13`) recouvrait l'IP de `network01` (`.9`) | Plage ramenée à `.11`–`.13` (3 adresses), avec vérification préalable des adresses libres | [Tenants](Tenants.md) |
| 24 | Avertissement `Invalid characters were found in group names` | Sans conséquence, documenté | [Dépannage](Depannage.md#avertissement--invalid-characters-were-found-in-group-names) |
| 25 | `pull` : `network01` `unreachable` (perte SSH passagère) | Étape `pull` ajoutée au README (11.2), conduite à tenir documentée | [Dépannage](Depannage.md#kolla-ansible-pull--unreachable) |
| 26 | Section SELinux : `ausearch` sans `sudo`, périmètre non précisé | Réduite aux 3 contrôleurs, avec `sudo` et `getsebool` | README 6.4 |
| 27 | `dnf` : `nothing provides openssl-libs` (miroirs désynchronisés) | Note et solution ajoutées à l'étape 8.1 | [Dépannage](Depannage.md#dnf--nothing-provides-openssl-libs) |
