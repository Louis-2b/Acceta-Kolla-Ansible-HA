# Créer et distribuer des tenants

Ce guide suppose le cloud déployé et validé (étapes 1 à 12 du [README](../README.md)).

Un **tenant** correspond à un **projet** OpenStack : un espace isolé avec ses VMs, ses réseaux, ses volumes et ses quotas. Vous restez l'administrateur ; chaque personne reçoit un utilisateur avec le rôle `member` sur son projet, jamais `admin`.

Toutes les commandes `openstack` se lancent depuis `controller01`, avec :

```bash
source ~/kolla-ansible/bin/activate
source /etc/kolla/admin-openrc.sh
```

> Les valeurs d'exemple (adresses, noms) sont à adapter. Les commandes n'ont pas été exécutées sur votre cloud : testez-les d'abord sur un projet jetable.

---

## 1. Réseau externe partagé (une seule fois)

C'est le réseau d'où viennent les adresses flottantes. Il correspond à `ens192` (`neutron_external_interface`), vue par Neutron comme le réseau physique `physnet1` (valeur par défaut de Kolla pour la première interface externe).

```bash
openstack network create public \
  --external --share \
  --provider-network-type flat \
  --provider-physical-network physnet1

openstack subnet create public-subnet \
  --network public \
  --subnet-range 172.20.10.0/28 \
  --gateway 172.20.10.1 \
  --allocation-pool start=172.20.10.11,end=172.20.10.13 \
  --dns-nameserver 1.1.1.1 \
  --no-dhcp
```

> ⚠️ **Plage très limitée.** Le sous-réseau `172.20.10.0/28` ne compte que 14 adresses utilisables. Adresses occupées d'après le tableau d'architecture du README : la passerelle `.1` (supposée), les 6 nœuds (`.3`, `.6`, `.7`, `.8`, `.9`, `.10`) et la VIP `.14`. Restent a priori libres : `.2`, `.4`, `.5`, `.11`, `.12`, `.13`. L'exemple ci-dessus utilise `.11` à `.13`, soit **3 adresses**.
>
> Chaque routeur de tenant consomme **une** adresse de cette plage pour sortir sur Internet, et chaque adresse flottante en consomme une autre : 3 adresses suffisent pour un seul tenant (un routeur et deux adresses flottantes). Prévoyez un réseau externe plus large (un `/24` dédié ou un VLAN) avant d'ouvrir le cloud à plusieurs personnes.
>
> **Avant de créer le sous-réseau**, vérifiez que ces adresses sont réellement libres : elles ne doivent être attribuées ni par le DHCP de votre réseau ni à un autre appareil. Un `ping -c 1 -W 1 172.20.10.11` sans réponse ne le prouve pas (certains appareils ignorent le ping) : consultez aussi les baux DHCP de votre routeur. Vérifiez enfin la passerelle réelle (`ip route` sur un nœud) : le `.1` n'est qu'une hypothèse.

---

## 2. Flavors, images

Les flavors définissent la taille des VMs.

```bash
openstack flavor create m1.small  --vcpus 1 --ram 2048 --disk 20
openstack flavor create m1.medium --vcpus 2 --ram 4096 --disk 40
openstack flavor create m1.large  --vcpus 4 --ram 8192 --disk 80
```

Une image publique est visible par tous les tenants. Utilisez une image « cloud » au format qcow2 de la distribution voulue (exemple avec Ubuntu 24.04) :

```bash
curl -LO https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

openstack image create "ubuntu-24.04" \
  --file noble-server-cloudimg-amd64.img \
  --disk-format qcow2 --container-format bare \
  --public
```

Les images stockées dans Glance sont écrites dans `/mnt/glance` (NFS depuis `storage01`) : vérifiez l'espace disponible avant de téléverser plusieurs images.

---

## 3. Un projet, un utilisateur, des quotas

Remplacez `alice` par le nom du tenant.

```bash
openstack project create --description "Tenant Alice" alice
openstack user create --project alice --password-prompt alice
openstack role add --project alice --user alice member
```

Sans quotas, un tenant peut consommer tout le cloud. Définissez-les pour chaque projet :

```bash
PROJECT_ID=$(openstack project show alice -f value -c id)

openstack quota set \
  --instances 5 --cores 8 --ram 16384 \
  --volumes 5 --gigabytes 100 --snapshots 10 \
  --networks 3 --subnets 3 --routers 1 \
  --floating-ips 1 --secgroups 10 \
  "$PROJECT_ID"

openstack quota show "$PROJECT_ID"
```

---

## 4. Ce que le tenant fait ensuite

Le tenant se connecte à Horizon sur `https://openstack.tubie.lan` (voir l'étape 12.5 du README pour la CA privée) avec :

| Champ | Valeur |
|-------|--------|
| Domaine | `Default` |
| Utilisateur | `alice` |

Il crée lui-même son réseau privé, son routeur et sa première VM. Équivalent en ligne de commande, avec un fichier `clouds.yaml` (adaptez les valeurs) :

```yaml
clouds:
  alice:
    auth:
      auth_url: https://openstack.tubie.lan:5000
      username: alice
      project_name: alice
      user_domain_name: Default
      project_domain_name: Default
    region_name: RegionOne
    identity_api_version: 3
    cacert: /chemin/vers/root.crt
```

```bash
export OS_CLOUD=alice

openstack network create net-priv
openstack subnet create subnet-priv --network net-priv \
  --subnet-range 192.168.10.0/24 --dns-nameserver 1.1.1.1
openstack router create r1
openstack router add subnet r1 subnet-priv
openstack router set r1 --external-gateway public

openstack keypair create --public-key ~/.ssh/id_ed25519.pub ma-cle
openstack security group rule create --proto tcp --dst-port 22 default
openstack security group rule create --proto icmp default

openstack server create vm1 \
  --flavor m1.small --image ubuntu-24.04 \
  --network net-priv --key-name ma-cle

openstack floating ip create public
openstack server add floating ip vm1 <ADRESSE_FLOTTANTE>
```

Le fichier `root.crt` est la CA de `/etc/kolla/certificates/ca/root.crt` : remettez-le à chaque tenant avec ses identifiants.

---

## 5. Isolation et bonnes pratiques

- **Jamais `admin` pour un tenant.** Rôle `member` pour qui crée des ressources, `reader` pour la lecture seule.
- **Quotas systématiques** (étape 3), y compris sur les adresses flottantes et les routeurs.
- **Réseaux** : seul `public` est partagé (`--share`). Les réseaux privés des tenants ne le sont pas.
- **Images** : rendez publiques (`--public`) seulement les images de confiance. Les images d'un tenant restent privées.
- **Mots de passe** : transmettez-les par un canal sûr et demandez un changement à la première connexion.
- **Sauvegardes** : la sauvegarde Cinder est désactivée (Swift n'est pas disponible avec 2026.1) : les volumes des tenants ne sont **pas sauvegardés**. Prévenez vos tenants et voir [`HA-Roadmap.md`](HA-Roadmap.md).
- **Domaines Keystone** : un domaine par groupe de tenants permet de déléguer la gestion des utilisateurs. Pour commencer, le domaine `Default` suffit. Si vous utilisez d'autres domaines, vérifiez que Horizon affiche le champ « Domaine » à la connexion (support multi-domaines de Horizon, à contrôler dans votre version).
