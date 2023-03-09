# Boundary Demo

Providing remote access to applications and systems requires secure routing 
to the destination and credentials to authenticate the user. Traditionally, 
you achieve this using a Virtual Private Network (VPN) or a Bastion server to 
bridge into the private network. Credentials are generally provided individually, 
created as part of a manual process, and with password rotation on a best-intention 
basis. This is problematic as access is usually too broad, difficult to audit, 
and complex to maintain. 

In a zero-trust world, access is granted from point to point, not to the network 
edge; credentials are unique to the session, and everything is fully auditable. 
HashiCorp Boundary and Vault provide this solution giving you greater control
over access to your systems.

In this talk, Rob and Nic will walk you through the steps needed to configure Boundary 
and Vault showing you how to provide secure access to typical cloud-based systems 
like Kubernetes and virtual machines.

## General config

### Environment variables

```shell
# Boundary org id
export boundary_org_id=<myorg>

# Boundary scope
export boundary_scope_id=<myscope>

# Boundary human user
export boundary_username=<username>

# Boundary human user password
export boundary_password=<user password>

# Boundary auth method
export boundary_auth_method_id=<user auth method>

# Boundary server address
export BOUNDARY_ADDR="https://<cluster id>.boundary.hashicorp.cloud"

# Shipyard variables needed to auto configure workers
export SY_VAR_boundary_cluster_id=<cluster id>
export SY_VAR_boundary_username=<worker username>
export SY_VAR_boundary_password=<worker password>
export SY_VAR_boundary_auth_method_id=<worker auth method>
```

### Authenticating to Boundary

To log into boundary the following command can be used

**Boundary Authenticate**
```shell
boundary authenticate password \
  -password="env://boundary_password" \
  -login-name=njackson \
  -auth-method-id=${boundary_auth_method_id} \
  -format=json \
  | jq -r .item.attributes.token > .boundary_token
```

## Flow
* Explain problem with existing Bastion setup
* SSH
  - Problem 1: You need Access without Bastion
    - Show how to deploy and configure boundary worker using username password
    - Explain how to use Vault plugin to provide worker auth replacing hardcoded
      details
  - Problem 2: You need SSH creds
    - Show how to configure one-time access for the ssh server using PAM
      to generate credentials
    - Boundary can inject creds, but it needs access to Vault, show how to register
      a boundary worker for Vault
    - Show how to create a credentials store
    - Show how to inject creds
* Database
  - Problem 1: How to access the database
    - Show how to configure and inject dynamic db credentials / separated by role
* Nomad Job (census)
  - Problem 1: How to access workloads running in highly dynamic environments
    the issue is not access but managing targets.
    - Show how to run a boundary Worker in Nomad
    - Start an application on Nomad, show dynamic ports
    - Register a target
    - Re-allocate, watch everything turn to dust port and location has changed
    - Show Census to manage dynamic targets
  - Problem 2: You are using consul service mesh
    - Show pattern where Boundary worker is running as a sidecar

## Providing access to Virtual Machines

Providing access to virtual machines requires two core capabilities
* Access to the machine itself
* Credentials to log into the machine

First, let's see how Boundary can be used to provide access to the machine.

### Creating a secure tunnel to access SSH in a private VPC with Boundary

The network for the `frontend` VPC is private and other than the public port for
our API server no other access is available into the network.

To create a secure SSH tunnel we need to have connectivity to the VM's on port 22
this can be achieved by using Boundary. If we deploy a Boundary worker into the 
`frontend` VPC that worker makes an outbound connection to the public HCP Boundary
workers. This enables connections to flow from the public internet securely into
the private VPC without the need for opening any ports. Let's see how this works.

### Configuring a boundary worker

To run the boundary worker we first need to configure it; the following configuration
file is an example config for configuring a boundary worker.

*example_worker_config.hcl*

```javascript
hcp_boundary_cluster_id = "my_cluster_id"

listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
}

worker {
  auth_storage_path="/boundary/auth_data"

  controller_generated_activation_token = "my_token"

  tags {
    type   = ["frontend"]
  }
}
```

All Boundary workers require authentication with the Boundary server, this authentication
flow can be in one of two forms:
* Controller lead
* Worker lead

#### Controller lead
With controller lead a token generated from the boundary server must be pre-populated
into the workers configuration.

#### Worker lead
With worker lead, the worker will start and will generate a token that must be manually
entered into the Boundary UI or API to authorize the worker.  

The core complexity in both of these approaches is how you manage workers in highly
ephemeral environments like autoscaling groups. Manually approving workers may be 
fine for ad-hoc registration but it is not sustainable. 

Therefore, we need to look at how we can automatically generate this token and use 
the controller lead workflow.

To generate the token you can use the following command. This generates a token
that can be used in the configuration.

**Terminal Snippet: Boundary Worker Create**

```shell
boundary-worker workers create \
  controller-led \
  -token="file://.boundary_token" 
```

```shell
Worker information:
  Active Connection Count:                 0
  Controller-Generated Activation Token:   neslat_2KrJYaCupLFeDWBLUM15SpA
  Created Time:                            Wed, 08 Mar 2023 09:51:42 GMT
  ID:                                      w_mRqWDwy8q3
  Type:                                    pki
  Updated Time:                            Wed, 08 Mar 2023 09:51:42 GMT
  Version:                                 1

  Scope:
    ID:                                    global
    Name:                                  global
    Type:                                  global

  Authorized Actions:
    no-op
    read
    update
    delete
    add-worker-tags
    set-worker-tags
    remove-worker-tags
```

However, there is a problem to run this command you need to be authenticated,
so first, you need to authenticate. Which means we also need to run this
command.

**Terminal Snippet: Boundary Authenticate**

```shell
boundary authenticate password \
  -password="env://boundary_password" \
  -login-name=${boundary_username} \
  -auth-method-id=${boundary_auth_method} \
  -format=json \
  | jq -r .item.attributes.token > .boundary_token
```

Let's look at building a script to automate this process

### Building a worker authenticate script

*Editing file ./frontend/files/boundary_worker/startup.sh*

First, let's define some variables that we can inject from the environment

**Worker Script Vars**

```bash
echo "[$(date +%T)] Generating controller led token for boundary worker"

# The name to use for the worker
worker_name="${worker_name}"

# The HCP cluster id, cluster id will be set in the system.d job as an environment var
cluster_id="${cluster_id}"

# Username and password used to obtain the worker registration token
username="${username}"
password="${password}"

# The auth id used for authentication
auth_method_id="${auth_method_id}"

# Base url for the HCP cluster
base_url="https://${cluster_id}.boundary.hashicorp.cloud/v1"
auth_url="${base_url}/auth-methods/${auth_method_id}:authenticate"
token_url="${base_url}/workers:create:controller-led"
```

Next we can authenticate with boundary, we are going to use curl rather than
the cli. We can use sed to parse the token out of the response. You could 
of course use `jq` but this approach has reduced dependencies.

**Worker Script Authenticate**

```bash
# Authenticate with Boundary using the username and password and fetch the token
echo "[$(date +%T)] Authenticating with Boundary controller"
auth_request="{\"attributes\":{\"login_name\":\"${username}\",\"password\":\"${password}\"}}"
resp=$(curl ${auth_url} -s -d "${auth_request}")
token=$(echo ${resp} | sed 's/.*"token":"\([^"]*\)".*/\1/g')
```

Now we have a token, you can use that to generate the worker token.

**Worker Script Controller Token**

```bash
# Generate the controller led token request
echo "[$(date +%T)] Calling boundary API to generate controller led token"
resp=$(curl ${token_url} -s -H "Authorization: Bearer ${token}" -d "{\"scope_id\":\"global\",\"name\":\"${worker_name}\"}")
controller_generated_activation_token=$(echo ${resp} | sed 's/.*"controller_generated_activation_token":"\([^"]*\)".*/\1/g')
worker_id=$(echo ${resp} | sed 's/{"id":"\([^"]*\)".*/\1/g')

# Write the worker id so we can use this to delete the worker on deallocation
echo "[$(date +%T)] Writing worker id file to ./worker_id"
echo ${worker_id} > ./worker_id
```

Once the token has been generated you can generate the config for the worker
including this token.

**Worker Script Config**

```bash
# Write the config
echo "[$(date +%T)] Writing config to ./worker_config.hcl"
cat <<-EOT > ./worker_config.hcl
  disable_mlock = true
  log_level = "debug"

  hcp_boundary_cluster_id = "${cluster_id}"

  listener "tcp" {
    address = "0.0.0.0:9202"
    purpose = "proxy"
  }

  worker {
    auth_storage_path="/boundary/auth_data"

    controller_generated_activation_token = "${controller_generated_activation_token}"
  
    tags {
      type   = ["vault"]
    }
  }
EOT

echo "[$(date +%T)] Generated worker config for worker: ${worker_id}"
```

One important point is that when you register a worker it will exist until 
it is removed. We want to clean up after ourselves so we can use the `trap`
command to catch the exit.

**Worker Script Trap**

```bash
# trap the interrupt so that the worker deregisters on exit
trap "/boundary/deregister.sh" HUP INT QUIT TERM USR1
```

This is combined with the following script to de-register the worker, you could
include this in a single file. However if you are using systemD then instead of
trap you can use `PostStop` to handle deregistration.

*Editing file ./frontend/files/boundary_worker/deregister.sh*

**Worker Script Deregister**

```bash
#!/bin/sh -e
echo "[$(date +%T)] Deregister boundary worker"

# Read the worker id from the file written on startup
worker_id=$(cat ./worker_id)

# Base url for the HCP cluster
base_url="https://${cluster_id}.boundary.hashicorp.cloud/v1"
auth_url="${base_url}/auth-methods/${auth_method_id}:authenticate"
dereg_url="${base_url}/workers/${worker_id}"

# Authenticate with Boundary using the username and password and fetch the token
echo "[$(date +%T)] Authenticating with Boundary controller"
auth_request="{\"attributes\":{\"login_name\":\"${username}\",\"password\":\"${password}\"}}"
resp=$(curl ${auth_url} -s -d "${auth_request}")
token=$(echo ${resp} | sed 's/.*"token":"\([^"]*\)".*/\1/g')

# Deregister the worker
echo "[$(date +%T)] Calling boundary API to delete the worker ${worker_id}"
curl ${dereg_url} -s -H "Authorization: Bearer ${token}" -X DELETE

echo "[$(date +%T)] Deregistered worker: ${worker_id}"

# Remove the auth folder
echo "[$(date +%T)] Remove auth folder"
rm -rf /boundary/auth_data
```

Finally we can run the boundary worker

*Editing file ./frontend/files/boundary_worker/deregister.sh*

**Worker Script Run**

```bash
boundary-worker server --config ./worker_config.hcl &
dpid=$!
wait $dpid
```

### Running the worker script

Now the script has been created let's log into the server and run this script

**Frontend Worker Exec**

```shell
docker exec -it boundary-worker-frontend.container.shipyard.run /bin/sh
```

Then run the script

```shell
cd /boundary
./startup.sh
```

### Connecting to the Worker

Now the worker is running we need to create a target in boundary in order
to connect to it.

**Target Create SSH**

```shell
boundary targets create ssh \
   -token="file://.boundary_token" \
   -name="vm" \
   -description="SSH access for virtual machine" \
   -default-port=22 \
   -address=vm.container.shipyard.run \
   -scope-id=${boundary_scope_id} \
   -egress-worker-filter='"/name" == "frontend"'
```

Connect to the server

```shell
boundary connect ssh \
  -token="file://.boundary_token" \
  -target-id=<my target> -- -l root -i ./shipyard/frontend/files/ssh_keys/id_rsa
```

### Automatically injecting credentials from Vault

One of the benefits of Boundary is that you never need to have the credentials
for the machine your are connecting to. In the previous example we had the
credentials for the server. Let's now see how we can inject the credentials
automatically from Vault.

First we need to add the private key as a secret to Vault

```shell
vault kv put secret/vm \
  username=root \
  private_key=@./shipyard/frontend/files/ssh_keys/id_rsa
```

Boundary will need to access this secret so we need to create a policy for
the boundary controller.

*create file secrets_policy.hcl*

**Vault Secrets Policy**

```hcl
path = "secret/data/vm" {
  capabilities = ["read"]
}
```


For Boundary to use Vault secrets it needs to be able to authenticate
to do this we are going to configure Boundary with an orphaned Vault token.

We can do that with the following command:

**Vault Token Create**

```shell
vault token create \
  -period=30m \
  -format=json \
  -orphan=true \
  -policy=boundary-controller-token \
  -policy=boundary-controller-secrets \
  -no-default-policy=true \
  -renewable=true
```

This creates an orphaned token for Boundary, Boundary will need to manage
the lifecycle of this token so in order for it to do that you need the
following policy in addition to the secrets.

*Create file controller_policy* 

**Vault Controller Policy**

```hcl
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}

path "sys/leases/revoke" {
  capabilities = ["update"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}
```

Let's add both of these policies to Vault

**Vault Write Policy**

```shell
vault policy write boundary-controller-secrets secrets_policy.hcl
vault policy write boundary-controller-token controller_policy.hcl
```

Now that the policy has been created you need to create a credentials store,
a credentials store enables the Boundary controller to retrieve secrets from Vault.
It is possible to have multiple credential stores with differing secrets access
or even different Vault clusters.

```shell
boundary credential-stores create vault \
  -token="file://.boundary_token" \
  -scope-id "${boundary_scope_id}" \
  -vault-address "http://10.0.3.210:8200" \
  -vault-token "$(vault token create \
    -period=30m \
    -format=json \
    -orphan=true \
    -policy=boundary-controller-token \
    -policy=boundary-controller-secrets \
    -no-default-policy=true \
    -renewable=true | jq -r .auth.client_token)"
```

When we run this command we actually get an error

```shell
Error from controller when performing create on vault-type credential store

Error information:
  Kind:                Internal
  Message:             credentialstores.(Service).createInRepo: unable to create credential store: vault.(Repository).CreateCredentialStore: unable to lookup
  vault token: vault.(client).lookupToken: vault: http://vault.container.shipyard.run:8200: unknown: error #0: Get
  "http://vault.container.shipyard.run:8200/v1/auth/token/lookup-self": dial tcp 127.0.0.1:8200: connect: connection refused
  Status:              500
  context:             Error from controller when performing create on vault-type credential store
```

The reason for this is that Boundary can not validate the location of the Vault sever,
the reason for this is that Vault is not public. It is actually inside our Vault VPC.

No problem here, we can actually use Boundary to solve this issue, by having a 
boundary worker proxy connections to Vault.

```shell
boundary credential-stores create vault \
  -token="file://.boundary_token" \
  -scope-id "${boundary_scope_id}" \
  -vault-address "http://10.0.3.210:8200" \
  -vault-token "$(vault token create \
    -period=30m \
    -format=json \
    -orphan=true \
    -policy=boundary-controller-token \
    -policy=boundary-controller-secrets \
    -no-default-policy=true \
    -renewable=true | jq -r .auth.client_token)" \
  -worker-filter='"/name" == "vault"'
```

The credentials store holds the connection to Vault however to inject secrets
into a target you need to define a credential library that shows exactly which
secrets to inject. For our SSH secret we can use the following command.
We are setting a `credential-type` of `ssh_private_key`.

```shell
boundary credential-libraries create vault \
  -token="file://.boundary_token" \
  -credential-store-id <cred store id> \
  -vault-path "secret/data/vm" \
  -name "vault-ssh-library" \
  -credential-type ssh_private_key
```

Then finally you associate that credential library with the target that 
you created earlier.

```shell
boundary targets add-credential-sources \
  -token="file://.boundary_token" \
  -id <target id> \
  -injected-application-credential-source <cred source>
```

```shell
boundary connect ssh \
  -token="file://.boundary_token" \
  -target-id=<my target>
```

## Providing Access To Dynamic Workloads in Nomad 

Now we have seen how we can provide ssh access, let's look at how we can do
the same but this time for workloads running on Nomad.

### Ephemeral Workers

We learned how to run workers earlier on, but there was one core problem that 
we did not address. That problem is how we generate the credentials required
for a Boundary worker to join the cluster. When we tackled this with VMs the
approach was to use static credentials. We all know this is not a great approach
as should these credentials leak then they can be abused. 

To solve this problem let's see how we can use Vault to automatically generate
Boundary worker credentials.

We are going to use a custom Vault plugin to generate Boundary credentials.
This plugin can be downloaded from the following location.

[https://github.com/hashicorp-dev-advocates/vault-plugin-boundary-secrets-engine](https://github.com/hashicorp-dev-advocates/vault-plugin-boundary-secrets-engine)

The first step is to enable the plugin in Vault

```shell
vault secrets enable boundary
```

Then we need to configure the Boundary plugin, passing it the location of the 
Boundary server and the user details. 

```shell
vault write boundary/config \
  addr=${BOUNDARY_ADDR} \
  login_name=${boundary_username} \
  password=${boundary_password} \
  auth_method_id=${boundary_auth_method_id}
```

Then we create a role that allows the generation of worker tokens

```shell
vault write boundary/role/worker \
  ttl=180 \
  max_ttl=360 \
  role_type=worker \
  scope_id=global
```

We can test this by running the following command:

```shell
vault read boundary/creds/worker worker_name="local worker"
```

You will see the worker registered in the Boundary UI, we can remove this worker
by revoking the lease.

```shell
vault lease revoke boundary/creds/worker/s5fqm0B0bAeX0ZVkrQqf8nQr
```

The worker will now have been deleted from Boundary.

### Configuring the Nomad Job

Nomad will need to access this secret so we need to create a policy for
the boundary worker job

*create file worker_policy.hcl*

**Vault Secrets Policy**

```hcl
path = "boundary/creds/worker" {
  capabilities = ["read", "update"]
}
```

And then write this to Vault 

```shell
vault policy write boundary-worker worker_policy.hcl
```

Let's now create a Nomad job for running a worker

```hcl
```

### Deploying Census

First we need to create the secrets for the Nomad job we will use to run 
Census.

```
vault kv put secret/census \
  boundary_username="${boundary_username}" \
  boundary_password="${boundary_password}" \
  boundary_org_id="${boundary_org_id}" \
  boundary_auth_method_id="${boundary_auth_method_id}"
```

*create file census_policy.hcl*

**Vault Secrets Policy**

```hcl
path "secret/data/census" {
  capabilities = ["read"]
}
```

And then write this to Vault 

```shell
vault policy write boundary-census census_policy.hcl
```

Deploy the API job

```shell
nomad run ./shipyard/backend/files/jobs/api.hcl
```

Run the worker to connect to the api

```shell
boundary connect -target-id ttcp_b0Y1moFWMW -token="file://.boundary_token"
```