# Self-Managed Kubernetes Cluster deployement with Terraform and Ansible
This repositrory contains the files to deploy a Kubernetes cluster on AWS. The infrastructure is deployed with Terraform wheras the cluster configuration is done with Ansible.

🧠 The core idea

* Terraform is responsible for creating the infrastructure
* Ansible is responsible for configuring it
* The “contract” between them is inventory + variables

You'll find 2 versions for deploying a Kuberneted Cluster

* version v1: In this version the cluster is made of 1 control node + 1 worker node. Both nodes are not not in an ASG.
* version v2: In this version we create 1 control node with 2 worker nodes created in an ASG. That way we can easily create an many worker nodes as we need.


Prerequisites:

* Install awscli, Terraform, and Ansible on your local machine. Make sure you have a valid AWS account with privilege to create resources (EC2, S3).

* If not done already create a key pair named kube-access in AWS and retrieve the private key

	$ aws ec2 create-key-pair --key-name kube-access --query 'KeyMaterial' --output text > kube-access.pem

* After saving the private key file, set the correct permissions:

	$ chmod 400 kube-access.pem

* Create a user terraform in AWS, create a profile for this user with awscli and export the following environment variable for Terraform

    $ export ACCESS_KEY=$(aws configure get aws_access_key_id --profile terraform)

    $ export SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile terraform)

    $ export AWS_DEFAULT_REGION=$(aws configure get region --profile terraform)

## Version v1:

In this version we use Terraform to generate Ansible inventory file dynamically. To do so Terraform uses a template file that it polulates at runtime. Once the infrastructure is created you can check connectivity wiith "ansible -m ping all".

```
v1
├── ansible
│   ├── ansible.cfg
│   ├── inventory
│   ├── ssh-key
│   │   └── kube-access.pem
│   ├── playbooks
│   │   ├── k8s-cluster-setup.yaml
│   │   ├── k8s-common.yaml
│   │   ├── k8s-control.yaml
│   │   └── k8s-workers.yaml
│   └── templates
│       ├── custom-resources.yaml.j2
│       └── kubeadm-config.yaml.j2
└── terraform
    ├── inventory.tpl
    ├── main.tf
    └── variable.tf
```

To deploy v1, navigate to the terraform directory and run

If not done already initialize your terraform workspace.

    $ terraform init

then preview the changes Terraform will make with

    $ terraform plan

then makes the changes defined by your plan to create all resources with

    $ terraform apply

Terraform will create the inventory file that ansible uses to access the node. To check that the nodes are reachable, navigate to the ansible directory and run

    $ ansible -m ping all

To setup the K8s cluster, navigate to the ansible directory and run

    $ ansible-playbook playbooks/k8s-cluster-setup.yaml   

To delete all resources, go to the terraform directory and run

    $ terraform destroy -auto-approve

## version v2:

With this version we create 1 control node with 2 worker nodes created in an ASG. In this version we enable the AWS inventory plugins in ansible to dynamically retrieve the nodes public DNS name.

```
v2
├── ansible
│   ├── ansible.cfg
│   ├── aws_ec2.yaml
│   ├── playbooks
│   │   ├── k8s-cluster-setup.yaml
│   │   ├── k8s-common.yaml
│   │   ├── k8s-control.yaml
│   │   └── k8s-workers.yaml
│   └── templates
│       └── kubeadm-config.yaml.j2
└── terraform
    ├── inventory.tpl
    ├── main.tf
    └── variable.tf
```

✅ Step 1: Make sure the AWS collection is installed

In this version you need amazom.aws collection for ansible. The EC2 inventory plugin lives in the amazon.aws collection.

To check if it's install run the command

    $ ansible-galaxy collection list | grep amazon.aws

if nothing shows up → install it:

    $ ansible-galaxy collection install amazon.aws

Also required (on your local machine) is the aws python sdk:

    $ pip install boto3 botocore

Verify boto3 is availavle

    python3 - <<EOF
    import boto3
    print("boto3 OK")
    EOF

✅ Step 2: Enable inventory plugins in ansible.cfg (THIS IS THE BIG ONE)

Ansible does not auto-enable dynamic inventory plugins unless configured.

Create or update ansible/ansible.cfg:

    [defaults]
    inventory = ./ansible
    host_key_checking = False
    interpreter_python = auto_silent

    [inventory]
    enable_plugins = aws_ec2, yaml, ini

📌 Important

enable_plugins is mandatory
aws_ec2 must be explicitly listed

✅ Step 3: Verify your inventory file path & name

Your inventory must end in .yml or .yaml and live in the inventory directory.


To deploy v2, navigate to the terraform directory and run

    $ terraform apply

To setup the K8s cluster, navigate to the ansible directory and run

        $ ansible-playbook playbooks/k8s-cluster-setup.yaml

To delete all resources, go to the terraform directory and run

    $ terraform destroy -auto-approve
