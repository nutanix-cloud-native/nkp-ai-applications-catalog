# Recover AIRM Secrets

Use this guide when an AIRM Secret is deleted or lost, or when AIRM fails with a credential error. Typical signs:

- A pod cannot start because a Secret is missing (`CreateContainerConfigError` or `FailedMount`).
- A stage fails with a credential message.
- A service rejects its own database or broker login.

## Start here

1. Confirm you are on the right cluster. See [Before you start](#before-you-start).
2. Find your symptom in [Find the Secret](#find-the-secret).
3. Check whether a backup can restore it. See [Step 2](#step-2-restore-from-backup).
4. If not, follow the Secret's section in [Step 3](#step-3-recover-each-secret-manually).
5. Restart only what that section says, then [verify](#step-4-restart-consumers-and-verify).

Run each block as one unit. Read the **Expect** line after each block. If the output is different, stop.

## Before you start

### Set up your terminal

Run this once in each terminal session:

```
kubectl config current-context
umask 077
RELEASE_NS=$(kubectl get kustomization -A -l airm.nutanix.com/stage -o jsonpath='{.items[0].metadata.namespace}')
echo "Release namespace: $RELEASE_NS"
```

**Expect:** the context is the cluster you intend to change, and the namespace is printed. If the namespace is blank, stop.

`umask 077` makes every file this terminal creates readable only by you.

Turn off command tracing. Tracing prints values, so it must stay off:

```
set -o | grep xtrace
```

**Expect:** `xtrace off`. If it says `on`, run `set +x` in bash, or `unsetopt xtrace` in zsh.

### Security rules

- Never type a secret value on the command line, and never paste one into a ticket, chat, or shell history. This guide passes values through pipes (`<(...)`) and stdin, so they stay out of history and out of the terminal output.
- Delete a Secret only when a step tells you to, and confirm its name before each `delete` or `create`.
- Do not generate a second value for the same Secret. If a step fails after a new value was written, use the value from that terminal session to retry. A second value causes a mismatch.
- Work on one Secret at a time. Finish its restart and checks before you start another.
- Record in your change ticket which steps you ran, when, and who approved them. Do not record any values.
- This procedure needs cluster-admin access, plus access to the `airm` and `keycloak` namespaces.

### Data safety

This guide changes Secrets, Pods, and Jobs. It does not change database data. The data lives in PersistentVolumeClaims (PVCs), and the PersistentVolumes behind them use the `Delete` reclaim policy. Deleting a PVC deletes its data.

- **Never delete a PVC, a StatefulSet, or the CNPG `Cluster` or RabbitMQ `RabbitmqCluster` object.** Deleting a StatefulSet can delete its PVCs. The RabbitMQ StatefulSet is set to delete its PVCs when it is deleted.
- **Do not uninstall or roll back the AIRM or Keycloak Helm release.** Do not delete the `airm` or `keycloak` namespaces.
- **Do not suspend, delete, or prune Flux Kustomizations or HelmReleases** to get unstuck. A stage that is removed can delete the objects it applied. Some stages set `prune: false`, including the database (05b), RabbitMQ operator (05a), CRD (07a), and Keycloak (03a) stages. Most other stages do not. Do not do this without a platform owner's approval in your change ticket.
- **Do not use `--all`, label selectors, or wildcards with `kubectl delete`.** Name each object.
- **Delete only the Pods and Jobs that a step names.** Deleting a Pod does not delete its PVC, so the data stays.
- **Velero backups here cover Secrets only, not PVC data.** Velero's backup of the `airm` and `keycloak` PersistentVolumes did not capture the data, and no volume snapshots exist. Do not treat a Velero backup as protection for the database or Keycloak data. The database needs its own backup, which is outside this guide.

### Stop if

- A command fails with an error you do not understand.
- The current context is not the cluster you intend to change.
- Your case is not in this guide.
- Any output shows a password, token, or key.
- A database check does not match the value you expect.

### Check the database before any change to it

Before you run `ALTER USER` or `ALTER ROLE`, confirm the database pod is the primary:

- **AIRM database (CloudNativePG):**

  ```
  kubectl get pod airm-infra-cnpg-cnpg-1 -n airm -o jsonpath='{.metadata.labels.cnpg\.io/instanceRole}{"\n"}'
  ```

  **Expect:** `primary`.

- **Keycloak database:**

  ```
  kubectl get pods -n keycloak
  ```

  **Expect:** `keycloak-postgresql-0` is the only database pod.

## Find the Secret

| You see | Secret | Go to |
|---|---|---|
| Pod event `CreateContainerConfigError` or `FailedMount` naming a Secret | The Secret named in the event | [Step 1](#step-1-find-what-is-missing) |
| airm-api logs `password authentication failed` | `airm-cnpg-user` | [airm-cnpg-user](#airm-cnpg-user) |
| Helm upgrade fails with `PASSWORDS ERROR`, or `keycloak-0` shows `FailedMount` for `keycloak-postgresql` | `keycloak-postgresql` | [keycloak-postgresql](#keycloak-postgresql) |
| Stage 03b fails with `failed to obtain Keycloak admin token`, or `keycloak-0` shows `FailedMount` for `keycloak` | `keycloak` | [keycloak](#keycloak) |
| Stage 09 fails with `one-time user secret is not available`, or the agent logs RabbitMQ authentication errors | `airm-rabbitmq-common-vhost-user` | [airm-rabbitmq-common-vhost-user](#airm-rabbitmq-common-vhost-user) |
| Database TLS errors (`tls: bad certificate`, `Instance Status Extraction Error`) | CNPG CA group | [Secrets owned by other components](#secrets-owned-by-other-components) |
| `airm-cnpg-superuser` missing, and stage 01 stops | `airm-cnpg-superuser` | [airm-cnpg-superuser](#airm-cnpg-superuser) |
| Public endpoint serves Traefik's default certificate | `airm-gateway-tls` | [Rerun group](#rerun-group) |

## Step 1: Find what is missing

Check every Secret this guide covers:

```
kubectl get secret airm-cnpg-user airm-cnpg-superuser airm-rabbitmq-common-vhost-user airm-rabbitmq-admin airm-user-credentials airm-secrets-airm airm-keycloak-admin-client airm-keycloak-ui-creds -n airm
kubectl get secret keycloak keycloak-postgresql keycloak-kcadmin -n keycloak
kubectl get secret airm-gateway-tls -n "$RELEASE_NS"
```

**Expect:** each Secret is listed. A line that says `NotFound` means that Secret is missing. Read the output, not the exit code.

> **Do not rerun stage 01 to recreate a manual-group Secret.** If the database exists, stage 01 stops when `airm-cnpg-user`, `airm-cnpg-superuser`, or `airm-rabbitmq-common-vhost-user` is missing. This is intentional. A new value would not match the database.
>
> To check whether the database exists:
>
> ```
> kubectl get clusters.postgresql.cnpg.io airm-infra-cnpg-cnpg -n airm
> ```
>
> If the Cluster exists, the database exists.

### Manual group

These Secrets hold values that the database or Keycloak already uses. Recover them from a backup ([Step 2](#step-2-restore-from-backup)) or by hand ([Step 3](#step-3-recover-each-secret-manually)).

| Secret | Namespace | Recovery |
|---|---|---|
| `airm-rabbitmq-common-vhost-user` | `airm` | Restore, or by hand (a new registration; the original credential is lost) |
| `keycloak` | `keycloak` | Restore, or by hand (also needs `keycloak-kcadmin`) |
| `keycloak-postgresql` | `keycloak` | Restore, or by hand |
| `airm-cnpg-user` | `airm` | Restore, or by hand (`ALTER ROLE`) |
| `airm-cnpg-superuser` | `airm` | Restore, or by hand (only while `enableSuperuserAccess` is `false`) |

### Rerun group

Do not restore or edit these by hand. Rerun the stage that creates them. See [Rerun a stage](#rerun-a-stage).

| Secret | Namespace | How it comes back |
|---|---|---|
| `airm-rabbitmq-admin` | `airm` | Rerun stage 01 (it creates the Secret only if it is missing), then stage 06. Restart airm-api only if stage 01 created a new value. No RabbitMQ restart is needed: stage 06 sets the `admin` password on the running broker. The server reads `default_user.conf` only when it first initializes its data |
| `keycloak-kcadmin` | `keycloak` | Rerun stage 03b |
| `airm-gateway-tls` | `$RELEASE_NS` | Rerun stage 11. A custom certificate must be restored from a backup. If no backup exists, stage 11 creates a self-signed development certificate, and clients will not trust it. Production needs its approved certificate in this Secret. Traefik reloads the certificate without a restart |
| `airm-user-credentials` | `airm` | Rerun stage 01, then stage 03b. Stage 03b resets the AIRM user's Keycloak password to the new value |
| `airm-keycloak-admin-client`, `airm-keycloak-ui-creds` | `airm` | Rerun stage 03b. It copies Keycloak's client secret into both Secrets. Restart the consumer only if the value changed ([Step 4](#step-4-restart-consumers-and-verify)) |
| `airm-secrets-airm` | `airm` | Rerun stage 01 (it creates the Secret only if it is missing). Restart airm-ui only if stage 01 created a new value |
**Note on `keycloak-kcadmin`:** Stage 03b reuses the Secret's current value. It generates a new one only if the Secret is missing. Every 03b run then sets the Keycloak `kcadmin` password to the Secret's value. Nothing copies a changed Keycloak password back into the Secret. If someone changes the `kcadmin` password in Keycloak by hand, the next 03b rerun reverts it to the Secret's value.

## Secrets owned by other components

These Secrets are created by a chart, an operator, or an external controller, not by our stages. For each one, restore from backup when a backup is configured ([Step 2](#step-2-restore-from-backup)). Otherwise, follow that project's documentation.

| Secret | Namespace | Owner | Recovery |
|---|---|---|---|
| `airm-infra-cnpg-cnpg-ca`, `airm-infra-cnpg-cnpg-server`, `airm-infra-cnpg-cnpg-replication` | `airm` | CloudNativePG operator | The operator recreates a missing Secret on its next reconciliation. A pod restart does not recreate it. Do not delete these Secrets by hand, because a new CA can break existing client and replication certificates and cause a temporary TLS outage. |
| `airm-infra-rabbitmq-rabbitmq-erlang-cookie` | `airm` | RabbitMQ cluster operator | Do not delete this Secret. If it is deleted, the operator creates a new value that is not applied to the running cluster. Restarting pods does not fix this and can break inter-node authentication. Restore it from backup when a backup is configured. This doc has no other procedure; follow the RabbitMQ documentation. |
| `airm-tls-secret`, `airm-agent-agent-webhook-cert` | `airm` | cert-manager | cert-manager recreates the Secret with a new certificate and key when it is missing. Anything that pins the old certificate must trust the new one. |
| `nkp-registry-creds` | `airm` | External Secrets Operator (`ExternalSecret`) | Recreated from its ExternalSecret source. |

## Step 2: Restore from backup

Use this step only when a backup exists. A restore brings back Secret values only, not database data or volumes. A restored database Secret works only if the database still has the matching password.

**Decision rule:** restore the missing Secret, then run that Secret's check in Step 3.

- If the check passes, you are done with that Secret. No restart is needed unless its section says so.
- If the check fails, the Secret and the database or service do not match. Use the manual fix in that Secret's section.

**Check freshness where possible.** A backup keeps the Secret value it had when the backup was taken. If the Secret changed after that, the restored value is old and may not match the live database or Keycloak. Where `managedFields` is kept on the cluster, compare the two times:

```
kubectl get secret <secret-name> -n <namespace> --show-managed-fields -o go-template='{{range .metadata.managedFields}}{{.time}}{{"\n"}}{{end}}'
kubectl get backups.velero.io <backup-name> -n "$VELERO_NS" -o jsonpath='{.metadata.creationTimestamp}{"\n"}'
```

**Expect:** the backup time is later than every time the Secret shows. If the Secret changed after the backup, do not restore it. Use its manual fix in [Step 3](#step-3-recover-each-secret-manually).

**If the first command prints nothing,** the Secret has no `managedFields` entries, so freshness cannot be confirmed. Empty output is not a pass. Do not use `-o json` or `-o yaml` for this check, because kubectl leaves `managedFields` out of that output unless you add `--show-managed-fields`. Do not restore a Secret you know changed after the backup. Otherwise, restore it as the backup step directs, then run its check in [Step 3](#step-3-recover-each-secret-manually). If its check fails, use its manual fix. If `keycloak-kcadmin` is missing, prefer the stage 03b rerun in the table above over a restore. Stage 03b makes Keycloak match whatever value the Secret holds, so logins keep working even if a restored value is older.

### 2.1 Check the backup

These checks use Velero. With another backup tool, run its equivalent checks and confirm that it can restore Secrets from the `airm` and `keycloak` namespaces.

1. Find the Velero namespace and confirm the backup location is available:

   ```
   VELERO_NS=$(kubectl get backupstoragelocations.velero.io -A -o jsonpath='{.items[0].metadata.namespace}') && [ -n "$VELERO_NS" ] && echo "Velero namespace: $VELERO_NS"
   kubectl get backupstoragelocations.velero.io -n "$VELERO_NS" -o custom-columns=NAME:.metadata.name,PHASE:.status.phase
   ```

   **Expect:** `PHASE` is `Available`.

2. List the backups:

   ```
   kubectl get backups.velero.io -n "$VELERO_NS" -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,ERRORS:.status.errors,CREATED:.metadata.creationTimestamp
   ```

   **Expect:** choose a backup with `PHASE` `Completed`. `ERRORS` is `0` or `<none>`. Velero shows `<none>` for a count of zero. When a daily scheduled backup (for example, the `velero-default` schedule) exists and is `Completed`, prefer its newest backup, because it covers all namespaces. Otherwise, use the newest `Completed` backup.

3. Check that the backup includes the namespace. Any exclusion or selector can drop a Secret:

   ```
   kubectl get backups.velero.io <backup-name> -n "$VELERO_NS" -o jsonpath='includedNamespaces={.spec.includedNamespaces} excludedNamespaces={.spec.excludedNamespaces} includedResources={.spec.includedResources} excludedResources={.spec.excludedResources} labelSelector={.spec.labelSelector} orLabelSelectors={.spec.orLabelSelectors}{"\n"}'
   ```

   **Expect:** `includedNamespaces` is empty (an empty list means all namespaces) or contains `airm` or `keycloak`. The exclusion and selector fields are empty.

If no completed backup includes the Secret, go to [Step 3](#step-3-recover-each-secret-manually).

### 2.2 Restore only the missing Secrets

The restore skips Secrets that already exist. It creates only the missing ones.

1. Set the variables. Replace the placeholder with the backup name from 2.1:

   ```
   BACKUP_NAME=<backup-name-from-2.1>
   RESTORE_NS=airm
   RESTORE_NAME=airm-restore-$(date -u +%Y%m%d%H%M)
   ```

   For the Keycloak namespace, set `RESTORE_NS=keycloak`.

2. Check that the restore name is free:

   ```
   kubectl get restores.velero.io "$RESTORE_NAME" -n "$VELERO_NS" --ignore-not-found
   ```

   **Expect:** no output.

3. Create the restore:

   ```
   RESTORE_FILE=$(mktemp)
   cat > "$RESTORE_FILE" <<EOF
   apiVersion: velero.io/v1
   kind: Restore
   metadata:
     name: $RESTORE_NAME
     namespace: $VELERO_NS
   spec:
     backupName: $BACKUP_NAME
     includedNamespaces:
     - $RESTORE_NS
     includedResources:
     - secrets
     existingResourcePolicy: none
   EOF
   kubectl apply -f "$RESTORE_FILE" && rm -f "$RESTORE_FILE"
   ```

4. Wait for the restore and check the result:

   ```
   kubectl wait restores.velero.io/"$RESTORE_NAME" -n "$VELERO_NS" --for=jsonpath='{.status.phase}'=Completed --timeout=10m
   kubectl get restores.velero.io "$RESTORE_NAME" -n "$VELERO_NS" -o jsonpath='phase={.status.phase} errors={.status.errors}{"\n"}'
   ```

   **Expect:** `phase=Completed`, and `errors` is `0` or empty, because Velero leaves zero counts empty. If the restore fails, stop.

5. For each restored Secret, run the check in its section in [Step 3](#step-3-recover-each-secret-manually). If the check passes, go to [Step 4](#step-4-restart-consumers-and-verify). If it fails, use that section's manual fix.

**Restore caveats**

- A restore creates every missing Secret in the backup, not only the one you need. Check each one.
- A restored value can be old. In testing, restores from a backup taken before the Secret's last change did not match. The restored Keycloak admin password failed to log in, the restored Keycloak database password failed to log in, and the restored RabbitMQ identity differed from the live Secret. Run each Secret's check after every restore.
### 2.3 Replace a Secret that still exists

Use this only when the Secret is wrong and must be replaced with the backup value. The restore skips existing Secrets, so the Secret must be deleted first.

Save the current Secret first. The saved file holds plaintext values. It is the only rollback copy, so keep it until the restore is verified:

```
D=$(mktemp -d)
kubectl get secret <secret-name> -n <namespace> -o yaml > "$D/<secret-name>.yaml"
echo "Saved to $D"
```

**Expect:** the path is printed, and the file exists.

Confirm that no controller will recreate the Secret before the restore runs. Cert-manager and the RabbitMQ operator can. Then delete it:

```
kubectl delete secret <secret-name> -n <namespace>
```

Run [2.2](#22-restore-only-the-missing-secrets) again. When the restore is verified, delete the saved copy:

```
rm -rf "$D"
```

## Step 3: Recover each Secret manually

Use this step when no backup covers the Secret, or when a restored Secret does not work. Each section gives what the Secret does, how to check whether it is the cause, the fix, and which consumer to restart.

### airm-rabbitmq-common-vhost-user

**What it is:** the RabbitMQ login for this cluster's agent. AIRM returns the password only once, during registration. It cannot be issued again.

**Symptom:** stage 09 fails with `cluster '<id>' is already registered ... but its one-time user secret is not available`.

**Check after a restore:** read the agent's logs:

```
kubectl logs deploy/airm-agent-agent -n airm --since=5m --tail=100
```

**Expect:** no RabbitMQ authentication or connection errors. If there are none, the restored Secret matches the broker, and nothing else is needed.

If the logs show authentication errors, the broker password does not match the restored Secret. Rerun stage 10 with step 3 of the fix below. Skip steps 1 and 2, because they replace the Secret you just restored. Then check the logs again. If the errors continue, stop.

**Fix.** The original password cannot be recovered. The agent works again with a new one.

1. Find the AIRM cluster ID from the registration Job log:

   ```
   CID=$(kubectl logs job/airm-registration -n "$RELEASE_NS" | grep -ioE "cluster '[^']+'" | sed -E "s/.*'([^']+)'.*/\1/" | sort -u) && [ "$(printf '%s\n' "$CID" | grep -c .)" -eq 1 ] && echo "Cluster ID: $CID"
   ```

   **Expect:** one cluster ID. If nothing prints, or more than one ID prints, stop. If the log is gone, stop. Do not guess the ID.

2. Create the Secret with the cluster ID and a new password. The password goes through a pipe and is never printed:

   ```
   PW=$(openssl rand -hex 16)
   kubectl create secret generic airm-rabbitmq-common-vhost-user -n airm \
     --from-literal=username="$CID" \
     --from-file=password=<(printf '%s' "$PW")
   unset PW
   ```

   **Expect:** `secret/airm-rabbitmq-common-vhost-user created`. If it says the Secret already exists, stop. Do not delete it without a step that tells you to.

3. Rerun stage 10. It sets the broker password from this Secret. Follow [Rerun a stage](#rerun-a-stage) with `JOB=airm-identity-sync` and `STAGE=10-identity-sync`.

4. Rerun stage 09. Follow [Rerun a stage](#rerun-a-stage) with `JOB=airm-registration` and `STAGE=09-bootstrap`.

   **Expect** this line in the new log:

   ```
   kubectl logs job/airm-registration -n "$RELEASE_NS" --tail=20
   ```

   The line should read `Cluster '<id>' is already registered and its identity is preserved`.

**Restart and verify:** restart the agent in [Step 4](#step-4-restart-consumers-and-verify).

### keycloak

**What it is:** the admin password for Keycloak's built-in `admin` user. Stage 03b uses it to configure Keycloak. The Keycloak chart generates this Secret at install, and our HelmRelease does not set `existingSecret`.

**Symptoms:** `keycloak-0` shows `FailedMount` for `keycloak`, a Helm upgrade fails with `PASSWORDS ERROR`, or stage 03b fails with `failed to obtain Keycloak admin token`.

**Start here:** run the login check. If it prints `admin login OK`, the Secret is good. Restart `keycloak-0` only if it is not Ready ([Step 4](#step-4-restart-consumers-and-verify)). If the check fails, or the Secret is missing, use the reset below.

Login check (read-only):

```
{ kubectl get secret keycloak -n keycloak -o jsonpath='{.data.admin-password}' | base64 -d; echo; } |
  kubectl exec -i -n keycloak keycloak-0 -c keycloak -- sh -c 'read -r ADMIN_PASSWORD; /opt/bitnami/keycloak/bin/kcadm.sh get realms --no-config --server http://localhost:8080 --realm master --user admin --password "$ADMIN_PASSWORD" >/dev/null && echo "admin login OK"'
```

**Expect:** `admin login OK`.

**Reset** (needs `keycloak-kcadmin` to still work). Run steps 1 and 2 in the same terminal.

1. Create a new value and store it in the `keycloak` Secret. If the Secret exists, only `admin-password` changes:

   ```
   NEW=$(openssl rand -hex 16)
   if kubectl get secret keycloak -n keycloak >/dev/null 2>&1; then
     kubectl patch secret keycloak -n keycloak --type merge --patch-file <(printf '{"data":{"admin-password":"%s"}}' "$(printf '%s' "$NEW" | base64)")
   else
     kubectl create secret generic keycloak -n keycloak --from-file=admin-password=<(printf '%s' "$NEW")
   fi
   ```

   **Expect:** `secret/keycloak patched` or `secret/keycloak created`. If the chart needs more keys, stop.

2. Set the `admin` password to the same value with the `kcadmin` account. Then run the login check above:

   ```
   : "${NEW:?NEW is not set. Run step 1 in this same terminal}"
   { kubectl get secret keycloak-kcadmin -n keycloak -o jsonpath='{.data.password}' | base64 -d; echo; printf '%s\n' "$NEW"; } |
     kubectl exec -i -n keycloak keycloak-0 -c keycloak -- sh -c '
       read -r KCADMIN_PASSWORD
       read -r NEW_PASSWORD
       /opt/bitnami/keycloak/bin/kcadm.sh set-password --no-config --server http://localhost:8080 --realm master --user kcadmin --password "$KCADMIN_PASSWORD" -r master --username admin --new-password "$NEW_PASSWORD"
     '
   ```

   **Expect:** no error, then `admin login OK` from the login check. `Invalid user credentials [invalid_grant]` means the `kcadmin` login failed. Either the `keycloak-kcadmin` password does not match, or brute-force protection has locked the account. Stop. Do not retry in a loop, because repeated failures can lock `kcadmin`.

   **Known exposure:** `kcadm.sh` takes the passwords as command-line arguments inside the Keycloak container. They are visible there for a moment, to anyone who can already run commands in that pod. Keep this step short.

3. Rerun stage 03b. Follow [Rerun a stage](#rerun-a-stage) with `JOB=airm-keycloak-config` and `STAGE=03b-keycloak-config`.

**Restart and verify:** [Step 4](#step-4-restart-consumers-and-verify).

### keycloak-postgresql

**What it is:** the two passwords for Keycloak's PostgreSQL database. `password` is for the `bn_keycloak` role, which Keycloak uses for the `bitnami_keycloak` database. `postgres-password` is for the `postgres` superuser. The database holds the real passwords, and the Secret is a copy. If they stop matching, Keycloak cannot connect.

The Keycloak Helm chart generates this Secret at install. Our HelmRelease does not set `existingSecret`, so a reinstall, or an upgrade after this Secret is deleted, generates new passwords that do not match the database. That is a deployment choice we own. Until the deployment changes, recover the Secret with the steps below, and never reinstall or upgrade to get past a missing Secret.

**Symptoms:** a Helm upgrade fails with `PASSWORDS ERROR: You must provide your current passwords when upgrading the release`, or `keycloak-0` shows `FailedMount` for `keycloak-postgresql`.

**Do not** do any of these while the Secret is missing. Each one creates a password the database does not have:

- Run `flux reconcile helmrelease airm-keycloak --force`, `helm upgrade`, or `helm rollback`.
- Upgrade the AIRM release.
- Pass a password with `--set` to get past `PASSWORDS ERROR`.

**Start here:** run the login check. If it prints `1`, the Secret matches the database. Restart `keycloak-0` only if it is not Ready ([Step 4](#step-4-restart-consumers-and-verify)).

Login check (read-only):

```
{ kubectl get secret keycloak-postgresql -n keycloak -o jsonpath='{.data.password}' | base64 -d; echo; } |
  kubectl exec -i -n keycloak keycloak-postgresql-0 -c postgresql -- sh -c 'read -r PGPASSWORD; export PGPASSWORD; exec psql -h 127.0.0.1 -U bn_keycloak -d bitnami_keycloak -tAc "select 1"'
```

**Expect:** `1`.

If the check fails, pick the case that matches:

- **`password` is missing and `postgres-password` exists:** use [partial loss](#partial-loss-only-password-is-missing). This is the common case.
- **Both keys are missing:** use [whole loss](#whole-loss-both-keys-are-missing-last-resort). Only with platform operator approval.
- **The Secret exists but the check fails:** do not change the database yourself. Stop.

#### Partial loss: only `password` is missing

Use this when `postgres-password` still exists.

1. Create a new value and set it on the `bn_keycloak` role. The superuser password comes from the Secret and goes through a pipe:

   ```
   NEW=$(openssl rand -hex 16)
   { kubectl get secret keycloak-postgresql -n keycloak -o jsonpath='{.data.postgres-password}' | base64 -d; echo; printf '%s\n' "\\set pw $NEW" "ALTER USER bn_keycloak PASSWORD :'pw';"; } |
     kubectl exec -i -n keycloak keycloak-postgresql-0 -c postgresql -- sh -c 'read -r PGPASSWORD; export PGPASSWORD; exec psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -f -'
   ```

   **Expect:** `ALTER ROLE`.

2. Write the same value to the Secret. Run this in the same terminal as step 1. If it fails, retry this step. Do not create another value:

   ```
   : "${NEW:?NEW is not set. Run step 1 in this same terminal}"
   kubectl patch secret keycloak-postgresql -n keycloak --type merge --patch-file <(printf '{"data":{"password":"%s"}}' "$(printf '%s' "$NEW" | base64)")
   ```

   **Expect:** `secret/keycloak-postgresql patched`.

3. Restart `keycloak-0` and verify: [Step 4](#step-4-restart-consumers-and-verify).

#### Whole loss: both keys are missing (last resort)

Use this only when no backup can restore the Secret and your platform operator has approved it in your change ticket.

**What this changes:** for a short time, any process inside the database pod can connect to PostgreSQL over its local socket without a password. Keycloak connects over the network, so its own connections are not affected by this change. The window is still open, so keep it short.

**Rules for this section:**

- Run steps 1 to 6 in one terminal, without a break.
- If a step fails, go straight to step 4 (roll back) before anything else.
- If the local rules are not `md5` in step 1, stop. This procedure does not support other rules, such as `scram-sha-256`.

1. Save the current authentication file and check its local rules. The copy holds no passwords:

   ```
   PGHBA=$(mktemp)
   kubectl exec -n keycloak keycloak-postgresql-0 -c postgresql -- cat /opt/bitnami/postgresql/conf/pg_hba.conf > "$PGHBA"
   grep '^local' "$PGHBA"
   ```

   **Expect:** lines that end in `md5`.

   Define the rollback, and set it to run if this terminal exits early:

   ```
   restore_pg_hba() {
     kubectl exec -i -n keycloak keycloak-postgresql-0 -c postgresql -- sh -c 'cat > /opt/bitnami/postgresql/conf/pg_hba.conf && kill -HUP "$(head -n 1 /bitnami/postgresql/data/postmaster.pid)"' < "$PGHBA"
   }
   trap restore_pg_hba EXIT
   ```

2. Change the local rules to `trust`, reload the server, and confirm that a local query works without a password:

   ```
   kubectl exec -n keycloak keycloak-postgresql-0 -c postgresql -- sed -i -E '/^local/ s/md5[[:space:]]*$/trust/' /opt/bitnami/postgresql/conf/pg_hba.conf
   kubectl exec -n keycloak keycloak-postgresql-0 -c postgresql -- sh -c 'kill -HUP "$(head -n 1 /bitnami/postgresql/data/postmaster.pid)"'
   kubectl exec -n keycloak keycloak-postgresql-0 -c postgresql -- psql -U postgres -d postgres -tAc "select 1"
   ```

   **Expect:** `1`. If the query asks for a password or fails, go to step 4.

3. Set new passwords for `postgres` and `bn_keycloak`:

   ```
   NEW_PG=$(openssl rand -hex 16)
   NEW_KC=$(openssl rand -hex 16)
   printf '%s\n' "\\set pg $NEW_PG" "\\set kc $NEW_KC" "ALTER USER postgres PASSWORD :'pg';" "ALTER USER bn_keycloak PASSWORD :'kc';" |
     kubectl exec -i -n keycloak keycloak-postgresql-0 -c postgresql -- psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f -
   ```

   **Expect:** two `ALTER ROLE` lines.

4. **Roll back the local rules.** Run this even if an earlier step failed. Then confirm the rules are back to `md5`:

   ```
   restore_pg_hba
   kubectl exec -n keycloak keycloak-postgresql-0 -c postgresql -- grep '^local' /opt/bitnami/postgresql/conf/pg_hba.conf
   trap - EXIT
   rm -f "$PGHBA"
   ```

   **Expect:** lines that end in `md5`. If any line does not, stop.

5. Create the Secret with both keys, using the values from step 3. Run this in the same terminal:

   ```
   : "${NEW_PG:?NEW_PG is not set. Run step 3 in this same terminal}"
   : "${NEW_KC:?NEW_KC is not set. Run step 3 in this same terminal}"
   kubectl create secret generic keycloak-postgresql -n keycloak \
     --from-file=postgres-password=<(printf '%s' "$NEW_PG") \
     --from-file=password=<(printf '%s' "$NEW_KC")
   unset NEW_PG NEW_KC
   ```

   **Expect:** `secret/keycloak-postgresql created`.

6. Restart `keycloak-0` and verify: [Step 4](#step-4-restart-consumers-and-verify).

### airm-cnpg-user

**What it is:** the database login for the AIRM API (`airm_user`, database `airm`).

**Symptom:** airm-api logs `password authentication failed`, or a login as `airm_user` with the Secret value fails.

**Check after a restore:** check the login with the restored value. **Expect:** `1`.

```
{ kubectl get secret airm-cnpg-user -n airm -o jsonpath='{.data.password}' | base64 -d; echo; } |
  kubectl exec -i -n airm airm-infra-cnpg-cnpg-1 -c postgres -- sh -c 'read -r PGPASSWORD; export PGPASSWORD; exec psql -h 127.0.0.1 -U airm_user -d airm -tAc "select 1"'
```

If it prints `1`, no database change and no restart is needed. If it fails with `password authentication failed`, use the fix below, starting at step 2. Do not run that fix without a platform owner's approval in your change ticket.

**Fix:**

1. If the Secret is missing, create it with a new value. Skip this step if the Secret exists:

   ```
   kubectl create secret generic airm-cnpg-user -n airm --from-literal=username=airm_user --from-file=password=<(printf '%s' "$(openssl rand -hex 16)")
   ```

2. Set the database role's password to the Secret's value. Confirm the primary check in [Before you start](#check-the-database-before-any-change-to-it) first. The block stops if the Secret cannot be read, so the role is never set to an empty password:

   ```
   PW=$(kubectl get secret airm-cnpg-user -n airm -o jsonpath='{.data.password}' | base64 -d)
   : "${PW:?could not read airm-cnpg-user. Nothing was changed}"
   { printf '%s\n' "\\set pw $PW" "ALTER ROLE airm_user PASSWORD :'pw';"; } |
     kubectl exec -i -n airm airm-infra-cnpg-cnpg-1 -c postgres -- psql -U postgres -d airm -v ON_ERROR_STOP=1 -f -
   unset PW
   ```

   **Expect:** `ALTER ROLE`.

**Restart and verify:** restart airm-api in [Step 4](#step-4-restart-consumers-and-verify). Only do this after the fix, because a running pod keeps the value it started with.

### airm-cnpg-superuser

No application uses this Secret. The database ignores it while `enableSuperuserAccess` is `false`.

**Check:**

```
kubectl get clusters.postgresql.cnpg.io airm-infra-cnpg-cnpg -n airm -o jsonpath='{.spec.enableSuperuserAccess}{"\n"}'
```

**Expect:** `false`. If it prints `true`, stop before you continue. The operator then applies this Secret to the `postgres` role.

**Fix** (only when the setting is `false` and the Secret is missing):

```
kubectl create secret generic airm-cnpg-superuser -n airm --from-literal=username=postgres --from-file=password=<(printf '%s' "$(openssl rand -hex 16)")
```

**Restart and verify:** none. No consumer needs a restart for this Secret.

## Step 4: Restart consumers and verify

A running pod keeps the Secret value it started with. Restart a consumer only when its section says to, or when its logs still show authentication errors after recovery.

| Secret | Restart (only if needed) | Verify |
|---|---|---|
| `airm-rabbitmq-common-vhost-user` | After a manual fix, or if the logs still show errors: `kubectl rollout restart deployment/airm-agent-agent -n airm` then `kubectl rollout status deployment/airm-agent-agent -n airm --timeout=5m` | `kubectl logs deploy/airm-agent-agent -n airm --since=5m --tail=100` shows no RabbitMQ authentication or connection errors |
| `keycloak`, `keycloak-postgresql` | After a fix that changes the database password, restart `keycloak-0`. The startup scripts read the password file only when the container starts. Otherwise, restart only if `keycloak-0` is not Ready: `kubectl delete pod keycloak-0 -n keycloak`, then `kubectl wait --for=condition=Ready pod/keycloak-0 -n keycloak --timeout=5m`. Keycloak is unavailable until it is ready | `kubectl get pod keycloak-0 -n keycloak` shows `1/1`, and `kubectl logs -n keycloak keycloak-0 --since=5m` shows no database errors |
| `airm-cnpg-user` | `kubectl rollout restart deployment/airm-api -n airm` then `kubectl rollout status deployment/airm-api -n airm --timeout=5m` (only after the manual fix) | `kubectl logs deploy/airm-api -n airm --since=5m` shows no `password authentication failed` |
| `airm-keycloak-admin-client` | Only if stage 03b changed the value: `kubectl rollout restart deployment/airm-api -n airm` then `kubectl rollout status deployment/airm-api -n airm --timeout=5m` | `kubectl logs deploy/airm-api -n airm --since=5m` shows no Keycloak authentication errors |
| `airm-keycloak-ui-creds`, `airm-secrets-airm` | Only if the value changed: `kubectl rollout restart deployment/airm-ui -n airm` then `kubectl rollout status deployment/airm-ui -n airm --timeout=5m` | `kubectl logs deploy/airm-ui -n airm --since=5m` shows no authentication errors |
If a deployment name is reported as `NotFound`, run `kubectl get deploy -n airm` and use the name it shows.

## Rerun a stage

Flux does not rerun a completed Job. To rerun a stage, delete its Job and ask Flux to reconcile the stage again.

| Stage | Job name | Label value |
|---|---|---|
| 01 | `airm-secret-init` | `01-secrets` |
| 03b | `airm-keycloak-config` | `03b-keycloak-config` |
| 06 | `airm-rabbitmq-config` | `06-rabbitmq-config` |
| 09 | `airm-registration` | `09-bootstrap` |
| 10 | `airm-identity-sync` | `10-identity-sync` |
| 11 | `airm-gateway-tls` | `11-gateway-tls` |

1. Set the two variables for the stage you rerun:

   ```
   JOB=airm-registration
   STAGE=09-bootstrap
   ```

2. Save the Job's logs, delete the Job, and ask Flux to reconcile the stage. Each line must succeed before the next one runs:

   ```
   D=$(mktemp -d)
   kubectl logs "job/$JOB" -n "$RELEASE_NS" > "$D/$JOB.log" &&
   kubectl delete job "$JOB" -n "$RELEASE_NS" &&
   kubectl annotate kustomization -n "$RELEASE_NS" -l airm.nutanix.com/stage="$STAGE" reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
   ```

   **Expect:** the Job is deleted, and the annotate command reports the stage Kustomization as annotated.

   If the saved log contains a password, token, or key, stop.

3. Wait for the new Job to finish:

   ```
   kubectl wait --for=condition=complete "job/$JOB" -n "$RELEASE_NS" --timeout=10m
   ```

   **Expect:** `condition met`.

   - `NotFound`: Flux has not created the Job yet. Wait 30 seconds and run the command again. If the Job still does not appear after a few minutes, check the stage's Kustomization:

     ```
     kubectl get kustomization -n "$RELEASE_NS" -l airm.nutanix.com/stage="$STAGE" -o jsonpath='{range .items[*].status.conditions[*]}{.type}={.status} {.reason} {.message}{"\n"}{end}'
     ```

     `Ready=False` with reason `DependencyNotReady` means an earlier stage is not Ready yet. Flux creates the Job after that stage is Ready. Check the stage named in the message, and fix that stage before you rerun this one. Do not delete the Job again.
   - Timeout or failure: run `kubectl logs "job/$JOB" -n "$RELEASE_NS"` and stop.

4. Delete the saved logs:

   ```
   rm -rf "$D"
   ```

## Cases without a documented procedure

Stop before you act in these cases:

- `keycloak` and `keycloak-kcadmin` are both lost, and no backup exists. Stage 03b fails with `failed to obtain Keycloak admin token`.
- `airm-cnpg-superuser` when `enableSuperuserAccess` is `true`.
- Any check in this guide does not match what you see.
