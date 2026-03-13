variable "vpc_name" {
  type    = string
  default = "kube-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "private_subnets" {
  default = {
    "private_subnet_1" = 1
    "private_subnet_2" = 2
  }
}

variable "public_subnets" {
  default = {
    "public_subnet_1" = 1
    "public_subnet_2" = 2
  }
}

variable "kube-bucket-name" {
  type    = string
  default = "kube-cluster-config"
}

variable "variables_sub_auto_ip" {
  description = "Set Automatic IP Assigment for Variables Subnet"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment in which the resource is deployed"
  type        = string
  default     = "dev"
}

variable "cluster" {
  description = "Name of the Kubernete cluster"
  type        = string
  default     = "kube1"
}

locals {
  team         = "devops"
  control_node = "control-${var.environment}-${var.cluster}"
  worker_node  = "worker-${var.environment}-${var.cluster}"
}
