# Provisionnement P2 — ImpactC sur Contabo

Ce runbook initialise les dépendances **dédiées à ImpactC** après le démarrage du socle `optimize-common-infra`. Il prépare les buckets privés MinIO, les identités applicatives à privilèges minimaux, les chemins de secrets Vault et l’AppRole de lecture du produit. Il ne déploie pas l’application elle-même : cette responsabilité sera assurée par le pipeline d’images et de déploiement P3.

> **Séparation obligatoire.** Le realm `impactc` Keycloak sert exclusivement aux comptes Responsable et Admin du backoffice. Les notifications métier transitent par `notification-hub` et son realm de service séparé. Ce script ne modifie ni le SMTP de Keycloak ni les identités de notification-hub.

## Préconditions

Le socle commun, Traefik et Vault doivent être démarrés sur le VPS. Vault doit avoir été initialisé, déverrouillé, et posséder le moteur KV v2 monté en `secret/`. Les réseaux externes `optimizesolux-common` et `traefik-public` doivent déjà exister.

| Élément          | État requis                                                 | Motif                                                                            |
| ---------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------- |
| MinIO            | Service `minio` sain sur `optimizesolux-common`             | Création des buckets et utilisateurs S3 ImpactC.                                 |
| Redis            | Service `redis` sain et protégé par mot de passe            | ImpactC utilisera uniquement l’index logique `6` et le préfixe BullMQ `impactc`. |
| Vault            | Service actif et déverrouillé, moteur `secret/` disponible  | Stockage des secrets applicatifs et émission de l’AppRole.                       |
| Keycloak         | Realm `impactc` déjà importé                                | Validation OIDC du seul backoffice.                                              |
| notification-hub | Client Credentials `impactc-notification-sender` disponible | Livraison des messages métier; aucune dépendance SMTP directe dans ImpactC.      |

## Préparer l’environnement du provisionneur

Copier le modèle d’environnement dans un emplacement privé du VPS, modifier toutes les valeurs `replace-with-*`, puis limiter ses permissions. Le fichier ne doit jamais être placé dans le dépôt ni copié dans une image Docker.

```bash
cd /opt/optimizesolux/common-infra
sudo install --directory --mode=0700 /root/impactc-provisioning
sudo cp deploy/impactc/provision-impactc.env.example /root/impactc-provisioning/.env
sudo chmod 0600 /root/impactc-provisioning/.env
sudoedit /root/impactc-provisioning/.env
```

Les secrets JWT doivent être distincts et aléatoires. `IMPACTC_CHAT_ENCRYPTION_KEY` est une clé AES-256 de **32 octets**. Les deux identités MinIO doivent être différentes l’une de l’autre, ainsi que du compte root MinIO : la première appartient à l’API et au worker ; la seconde n’est utilisée que par le workflow de publication APK.

| Valeur                                           | Destination Vault                                    | Utilisation                                     |
| ------------------------------------------------ | ---------------------------------------------------- | ----------------------------------------------- |
| `IMPACTC_DB_PASSWORD`                            | `secret/data/optimizesolux/impactc/db`               | PostgreSQL dédiée `impactc-db`.                 |
| Secrets JWT et clé chat                          | `secret/data/optimizesolux/impactc/auth`             | Membres JWT ImpactC et chiffrement de messages. |
| Mot de passe Redis, index `6`, préfixe `impactc` | `secret/data/optimizesolux/impactc/redis`            | BullMQ et readiness de l’API.                   |
| Identités et buckets MinIO                       | `secret/data/optimizesolux/impactc/s3`               | Photos de profil et publication APK.            |
| Issuer/audience backoffice                       | `secret/data/optimizesolux/impactc/oidc`             | Validation JWT Keycloak du backoffice.          |
| Client Credentials notification-hub              | `secret/data/optimizesolux/impactc/notification-hub` | Outbox transactionnelle ImpactC.                |

## Exécuter le provisionnement

Exécuter la commande en préservant les variables privées. Le script est idempotent : il réapplique les politiques MinIO, met à jour les utilisateurs et remplace les valeurs des chemins Vault explicitement gérés.

```bash
cd /opt/optimizesolux/common-infra
set -a
source /root/impactc-provisioning/.env
set +a
sudo -E ./deploy/impactc/provision-impactc.sh
```

Le script crée les buckets privés `impactc-media` et `impactc-mobile-releases`, puis applique deux politiques séparées. L’identité `impactc-media` peut exclusivement lire, écrire et supprimer les objets du bucket de photos. L’identité `impactc-mobile-releases` peut publier les APK et manifestes, sans accès aux médias membres.

Il crée également l’AppRole `impactc` avec la politique `impactc-read`, limitée aux chemins `secret/data/optimizesolux/impactc/*`. Son `role_id` et son `secret_id` sont écrits dans `/opt/optimizesolux/common-infra/private/impactc/approle.env`, avec le mode `0600`. Ce fichier est ignoré par Git et doit être transféré de manière contrôlée au service de déploiement P3, jamais au code applicatif ni à un poste local.

## Vérifications opérationnelles

Le script réalise des contrôles de service et de politique. L’opérateur doit ensuite valider les résultats suivants avant de préparer une release applicative.

```bash
# Les chemins Vault doivent exister; ne pas afficher les valeurs dans un terminal partagé.
docker compose --project-name optimizesolux-common \
  --env-file .env --profile core exec -T vault \
  vault kv list secret/optimizesolux/impactc

# Vérifier les deux utilisateurs MinIO sans afficher leurs secrets.
docker run --rm --network optimizesolux-common minio/mc:RELEASE.2024-12-18T13-15-44Z \
  --help >/dev/null

# Le compose applicatif doit se rendre sans erreur de variable.
cd /opt/optimizesolux/impactc
docker compose --env-file .env -f deploy/docker-compose.prod.yml config >/dev/null
```

| Contrôle                         | Résultat attendu                                                                                                                      |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Bucket `impactc-media`           | Privé ; aucun téléchargement anonyme ; accès réservé à l’identité média.                                                              |
| Bucket `impactc-mobile-releases` | Privé ; accès d’écriture séparé pour la publication CI. La stratégie de distribution signée sera traitée avec la livraison mobile P3. |
| AppRole `impactc`                | Lecture des seuls chemins ImpactC ; pas de capacité de liste ou de lecture sur un autre produit.                                      |
| Redis                            | Aucun nouveau serveur Redis ; index `6` et préfixe `impactc` réservés dans le service commun.                                         |
| API / worker                     | Utiliser les mêmes secrets, des rôles de processus distincts, sans ports de base de données ni Redis publiés.                         |

## Rotation et reprise

Une rotation MinIO consiste à créer un nouvel accès, à mettre à jour le chemin Vault `s3`, à redéployer l’API/worker, puis à désactiver l’ancien accès après confirmation de la readiness. Une rotation JWT ou de clé de chat doit suivre un plan de compatibilité applicative : ne pas changer une clé de chiffrement de chat sans procédure de déchiffrement des données existantes.

En cas d’échec du provisionneur, ne pas supprimer les buckets ou chemins Vault existants. Corriger l’entrée manquante, relancer le script, puis réexécuter les vérifications. La procédure de restauration PostgreSQL et le rollback d’image restent hors du P2 et seront contrôlés par le lot P3.
