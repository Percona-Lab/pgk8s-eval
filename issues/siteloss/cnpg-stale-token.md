### Is there an existing issue already for this bug?

Related: #9273 (closed after the user removed `promotionToken` by hand). This report shows what happens when the demotion fails for that reason but automation carries on.

### Version

1.30.1 (barman-cloud plugin 0.15.1)

### What version of Kubernetes are you using?

1.35 (k3s v1.35.9+k3s1)

### What is your Kubernetes environment?

Self-managed: k3s on Linode VMs (2 vCPU / 4 GB), local-path storage

### How did you install the operator?

YAML manifest (`cnpg-1.30.1.yaml`), plugin from its release manifest

### What happened?

Two-site distributed topology (dr-a in site-a, dr-b in site-b, object store only). We did a token-based switch A→B (worked: 8.5 s, 0 lost writes). dr-b now carries `replica.promotionToken` in its spec.

Later, switching back B→A:

1. `kubectl patch cluster dr-b --type=merge -p '{"spec":{"replica":{"primary":"dr-a"}}}'` — **rejected by the webhook**:
   `The Cluster "dr-b" is invalid: spec.replicaCluster.token: Invalid value: "<token>": promotionToken is only allowed for primary clusters`
2. `kubectl patch cluster dr-a ... '{"spec":{"replica":{"primary":"dr-a","promotionToken":""}}}'` — **accepted**; dr-a promoted.

Result: both clusters were primary for ~170 s while three persistent clients kept writing to dr-b. All **5,604** writes acknowledged by dr-b in that window were missing from dr-a. When dr-b was finally demoted it could not follow (`requested timeline 3 is not a child of this server's history`), PostgreSQL stayed down, and dr-b reported `Cluster in healthy state`. It had to be rebuilt.

### Expected

Any of:
- The operator clears (or ignores) `promotionToken` once it has been consumed, so a later demotion is not rejected.
- The webhook message tells the user to remove `promotionToken` (today it reads as an invalid token).
- Docs for the distributed topology mention that the token must be removed from the spec before demoting that cluster again.

A runbook or GitOps pipeline that applies both manifests will otherwise produce two primaries with no warning.

### Reproduction

https://github.com/Percona-Lab/pgk8s-eval (`dr/`, `results/dr_cnpg-notoken*`). One run.

### Code of Conduct

- [x] I agree to follow this project's Code of Conduct
