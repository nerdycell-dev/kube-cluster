terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.20"
    }
    random = {
      source = "hashicorp/random"
    version = "3.1.0" }
  }
}

# Retrieve the list of regions
data "aws_region" "current" {}

#Retrieve the list of AZs in the current AWS region
data "aws_availability_zones" "available" {}

# Retreive ssh key name
data "aws_key_pair" "existing" {
  key_name = "kube-access"
}

# Show available AZs
output "available_azs" {
  value = data.aws_availability_zones.available.names
}

# Terraform Data Block - To Lookup Latest Ubuntu 22.04 AMI Image
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

#Deploy the public subnets
resource "aws_subnet" "public_subnets" {
  for_each                = var.public_subnets
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone       = tolist(data.aws_availability_zones.available.names)[each.value % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = var.variables_sub_auto_ip

  tags = {
    Name      = each.key
    Terraform = "true"
  }
}

#Define the VPC
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = var.vpc_name
    Environment = "dev"
    Terraform   = "true"
    Region      = data.aws_region.current.name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name      = "kube-cluster"
    Terraform = "true"
  }
}

# Create public route table
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public_subnets

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "random_id" "randomness" {
  byte_length = 16
}

resource "aws_s3_bucket" "tf-S3-bucket" {
  bucket = "terraform-bucket-${random_id.randomness.hex}"
  tags = {
    Name    = "My S3 Bucket"
    Purpose = "Intro to Resource Blocks Lab"
  }
}

resource "aws_s3_bucket_ownership_controls" "tf_bucket_acl" {
  bucket = aws_s3_bucket.tf-S3-bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Security group with rulle for SSH allowed only for your IP
resource "aws_security_group" "kube-security-group" {
  name        = "ssh_inbound"
  description = "Allow inbound traffic on tcp/22"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    description = "Allow ssh from the Internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NodePort Services
  ingress {
    description = "Kubernetes NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NodePort Services
  ingress {
    description = "Allow all traffic from this SG"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "k8s-access-sg"
    Terraform = "true"
  }
}

resource "aws_iam_instance_profile" "clusternode_profile" {
  name = "clusternode-profile"
  role = aws_iam_role.role.name
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "role" {
  name               = "clusternode-role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "s3_write" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:AbortMultipartUpload",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.tf-S3-bucket.bucket}",
      "arn:aws:s3:::${aws_s3_bucket.tf-S3-bucket.bucket}/*",
      "arn:aws:s3:::${var.kube-bucket-name}",
      "arn:aws:s3:::${var.kube-bucket-name}/*",
    ]
  }
}

# Create the policy
resource "aws_iam_policy" "s3_write" {
  name   = "clusternode-s3-write"
  policy = data.aws_iam_policy_document.s3_write.json
}


# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "s3_write_attach" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.s3_write.arn
}

# Create control node
resource "aws_instance" "control-node" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t3a.medium"
  subnet_id            = aws_subnet.public_subnets["public_subnet_1"].id
  key_name             = data.aws_key_pair.existing.key_name
  iam_instance_profile = aws_iam_instance_profile.clusternode_profile.name
  user_data            = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname 'control-kube1'
    EOF
  vpc_security_group_ids = [
    aws_security_group.kube-security-group.id
  ]
  tags = {
    Name  = local.control_node
    Role = "control"
    Env  = var.environment
    Cluster = var.cluster
    Terraform = "true"
  }

}

## Create worker node
#resource "aws_instance" "worker-node" {
#  ami                  = data.aws_ami.ubuntu.id
#  instance_type        = "t3.small"
#  subnet_id            = aws_subnet.public_subnets["public_subnet_2"].id
#  key_name             = data.aws_key_pair.existing.key_name
#  iam_instance_profile = aws_iam_instance_profile.clusternode_profile.name
#  user_data            = <<-EOF
#    #!/bin/bash
#    hostnamectl set-hostname 'worker-kube1'
#    EOF
#  vpc_security_group_ids = [
#    aws_security_group.kube-security-group.id
#  ]
#  tags = {
#    Name  = local.worker_node
#    Owner = local.team
#  }
#}

# Launch Template for worker nodes
resource "aws_launch_template" "worker" {
  name_prefix   = "k8s-worker-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type
  key_name      = data.aws_key_pair.existing.key_name

  vpc_security_group_ids = [
    aws_security_group.kube-security-group.id
  ]

  iam_instance_profile {
    name = aws_iam_instance_profile.clusternode_profile.name
  }

  user_data = base64encode(<<EOF
    #!/bin/bash
    apt-get update -y
    EOF
      )

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 20        # 🔥 Increase SSD size here (GB)
      volume_type           = "gp2"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name  = local.worker_node
      Env       = var.environment
      Role      = "worker"
      Cluster   = var.cluster
      Terraform = "true"
    }
  }
}

# Auto Scaling Group (desired = 2)
resource "aws_autoscaling_group" "workers" {
  name                = "k8s-workers-asg"
  desired_capacity    = 2
  min_size            = 0
  max_size            = 2
  vpc_zone_identifier = [
    for subnet in aws_subnet.public_subnets : subnet.id
  ]

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = local.worker_node
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "worker"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

#resource "local_file" "ansible_inventory" {
#  filename = "${path.module}/../ansible/inventory/hosts.ini"
#
#  content = templatefile("${path.module}/inventory.tpl", {
#    control_public_dns_name = aws_instance.control-node.public_dns
#    #worker_public_dns_name  = aws_instance.worker-node.public_dns
#    control_public_ip = aws_instance.control-node.public_ip
#    control_private_ip = aws_instance.control-node.private_ip
#    #worker_public_ip = aws_instance.worker-node.public_ip
#  })
#}

# Output
output "control_public_ip" {
  value = aws_instance.control-node.public_ip
}

output "control_public_dns_name" {
  value = aws_instance.control-node.public_dns
}

