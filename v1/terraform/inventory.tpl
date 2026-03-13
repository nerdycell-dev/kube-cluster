[control]
control_node ansible_host=${control_public_ip}

[workers]
worker1 ansible_host=${worker_public_ip}

[control:vars]
control_public_dns=${control_public_dns_name}
control_private_ip=${control_private_ip}
control_public_ip=${control_public_ip}
pod_cidr=10.245.0.0/16
kubernetes_version=v1.29.0

[workers:vars]
worker1_public_dns=${worker_public_dns_name}

[all:vars]
ansible_user=ubuntu
