# Private SNO on AWS with Bastion

This guide shows a simple way to deploy **Single Node OpenShift (SNO)** on AWS with:

* a **bastion host** in a public subnet
* the **SNO node** in a private subnet
* a **private Route 53 hosted zone**
* a **SOCKS tunnel** from your laptop to access the OpenShift console
* see more **Installing a private cluster on AWS**: https://docs.redhat.com/en/documentation/openshift_container_platform/4.15/html/installing_on_aws/installing-aws-private

---

## High-level deployment

```text
                             Your laptop
                                 |
                                 | SSH / Browser via SOCKS proxy
                                 v
  +------------------------------------------------------------------+
  |                    AWS VPC (ap-southeast-1)                      |  
  +------------------------------------------------------------------|
  |                   +----------------------+                       |
  |                   |   Bastion Host EC2   |                       |
  |                   |   Public subnet      |                       |
  |                   |   Public IP          |                       |
  |                   |   NAT Gateway for AWS|                       |
  |                   |   APIs and downloads |                       |
  |                   +----------+-----------+                       |
  |                              ^                                   |
  |                              |                                   |
  |                              | HTTPS / oc / ssh                  |
  |                              | DNS queries to VPC resolver       |
  |                              v                                   |
  +------------------------------------------------------------------+
  |                                                                  |
  |   +----------------------+         +---------------------------+ |
  |   | Route 53 Private     |         | OpenShift SNO Node        | |
  |   | Hosted Zone          |         | Private subnet            | |
  |   | aws.ocp.internal     |<------->| API / Ingress endpoints   | |
  |   | associated to VPC    |  DNS    | Cluster services          | |
  |   +----------------------+         +---------------------------+ |
  |                                                                  |
  +------------------------------------------------------------------+
```

---

## How it works

* Your **laptop** connects to the **bastion host** by SSH.
* The **bastion** is in a public subnet and has a public IP.
* The **SNO node** is in a private subnet and has no public IP.
* The private hosted zone **aws.ocp.internal** is associated with the VPC.
* The bastion can resolve and reach private cluster endpoints such as:

  * `api.sno415.aws.ocp.internal`
  * `console-openshift-console.apps.sno415.aws.ocp.internal`
* The private subnet uses the **NAT Gateway** for outbound access to AWS APIs and downloads.

---

## What Terraform creates

Terraform creates the AWS foundation only:

* VPC
* public subnet for bastion
* private subnet for SNO
* Internet Gateway
* NAT Gateway
* route tables
* security group for bastion
* private Route 53 hosted zone
* EC2 key pair for bastion access
* bastion EC2 instance

OpenShift itself is installed later from the bastion by using `openshift-install`.

---

## Step 1: Prepare Terraform variables

Copy the example file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Update at least these values:

```hcl
admin_cidr             = "0.0.0.0/0"
bastion_ssh_public_key = "ssh-ed25519 AAAA...your_local_machine_public_key..."
```

Notes:

* `admin_cidr = "0.0.0.0/0"` allows SSH from anywhere.
* You can replace it with your own public IP `/32` if you want stricter access.
* Example, you can create a key pair with PowerShell: `ssh-keygen -t ed25519 -C "bastion"`
* Then get public key for bastion_ssh_public_key: `cat $env:USERPROFILE\.ssh\id_ed25519.pub`

---

## Step 2: Configure AWS credentials locally

On the machine where you run Terraform:

```bash
aws configure
aws sts get-caller-identity
```

Set:

* AWS Access Key ID
* AWS Secret Access Key
* Region: `ap-southeast-1`

---

## Step 3: Run Terraform

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
terraform output
```

---

## Step 4: SSH to the bastion

From Windows PowerShell:

```powershell
ssh -i $env:USERPROFILE\.ssh\id_ed25519 ec2-user@<BASTION_PUBLIC_IP>
```

Replace `<BASTION_PUBLIC_IP>` with the Terraform output.

---

## Step 5: Install bind-utils on the bastion

Run on the bastion:

```bash
sudo dnf update -y
sudo dnf install -y bind-utils
```

Verify:

```bash
aws --version
dig github.com
```

---

## Step 6: Configure AWS credentials on the bastion

Because `openshift-install` will run from the bastion, the bastion also needs AWS credentials:

```bash
aws configure
aws sts get-caller-identity
```

Set:

* AWS Access Key ID
* AWS Secret Access Key
* Region: `ap-southeast-1`

---

## Step 7: Create an SSH key on the bastion for node access

Generate a key pair on the bastion:

```bash
ssh-keygen -t ed25519 -N '' -f ${HOME}/.ssh/ocp4-aws-key
cat ~/.ssh/ocp4-aws-key.pub
```

You will use the output of `cat ~/.ssh/ocp4-aws-key.pub` in `install-config.yaml` as `sshKey`.

---

## Step 8: Download OpenShift installer and client

Example below uses OpenShift `4.15.60`:

```bash
cd ~
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.15.60/openshift-install-linux.tar.gz
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.15.60/openshift-client-linux.tar.gz

tar -xzf openshift-install-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz

sudo mv openshift-install /usr/local/bin/
sudo mv oc kubectl /usr/local/bin/

openshift-install version
oc version --client
```

---

## Step 9: Create `install-config.yaml`

Do **not** use the interactive command `openshift-install create install-config` for this private deployment.

```bash
cd ~
vi install-config.yaml
```

Use this example:

```yaml
apiVersion: v1
baseDomain: aws.ocp.internal
metadata:
  name: sno415

publish: Internal

platform:
  aws:
    region: ap-southeast-1
    subnets:
      - subnet-REPLACE_WITH_PRIVATE_SNO_SUBNET_ID
    hostedZone: ZONEID_REPLACE_WITH_PRIVATE_HOSTED_ZONE_ID

controlPlane:
  name: master
  replicas: 1
  platform:
    aws:
      type: m6i.2xlarge
      rootVolume:
        size: 120

compute:
  - name: worker
    replicas: 0

networking:
  networkType: OVNKubernetes
  machineNetwork:
    - cidr: 10.10.0.0/16
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16

pullSecret: '<PASTE_PULL_SECRET_JSON_ON_ONE_LINE>'
sshKey: '<PASTE_OUTPUT_OF_cat_~/.ssh/ocp4-aws-key.pub>'
```

Replace:

* private subnet ID
* private hosted zone ID
* pull secret
* SSH public key

Get subnet and zone values from Terraform:

```bash
terraform output private_sno_subnet_id
terraform output private_hosted_zone_id
```

---

## Step 10: Deploy the SNO cluster

From the bastion:

```bash
cd ~
openshift-install create manifests --dir .
openshift-install create cluster --dir . --log-level=debug
openshift-install wait-for bootstrap-complete --dir . --log-level=debug
openshift-install wait-for install-complete --dir . --log-level=debug
```

---

## Step 11: Verify the cluster

Set kubeconfig:

```bash
export KUBECONFIG=~/auth/kubeconfig
```

Check status:

```bash
oc whoami
oc get nodes -o wide
oc get co
```

Getting the OpenShift console URL, username, and password:

```bash
echo "Console URL: https://$(oc get route console -n openshift-console -o jsonpath='{.spec.host}')" && \
echo "Username: kubeadmin" && \
echo "Password: $(cat ~/auth/kubeadmin-password)"
```

Check private DNS from the bastion:

```bash
dig api.sno415.aws.ocp.internal
dig console-openshift-console.apps.sno415.aws.ocp.internal
```

---

## Step 12: Access the OpenShift console from your laptop

Create a SOCKS tunnel from Windows PowerShell:

```powershell
ssh -i $env:USERPROFILE\.ssh\id_ed25519 -D 1080 ec2-user@<BASTION_PUBLIC_IP>
```

Keep that terminal open.

This creates a SOCKS proxy on:

* host: `127.0.0.1`
* port: `1080`

### Test the tunnel from another PowerShell window

```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 1080
curl.exe --proxy socks5h://127.0.0.1:1080 -k https://console-openshift-console.apps.sno415.aws.ocp.internal -I
```

### Configure Firefox

Recommended browser: **Firefox**

Set:

* SOCKS Host: `127.0.0.1`
* Port: `1080`
* SOCKS v5
* enable **Proxy DNS when using SOCKS v5**

Then open:

```text
https://console-openshift-console.apps.sno415.aws.ocp.internal
```

---

## Cleanup

Destroy in this order.

### First destroy the OpenShift cluster from the bastion

```bash
cd ~
openshift-install destroy cluster --dir . --log-level=debug
```

### Then destroy Terraform-managed AWS resources

```bash
terraform destroy
```

