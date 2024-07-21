module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.eks_cluster_name
  cluster_version = "1.29"
  cluster_endpoint_public_access  = true

  cluster_addons = {
    vpc-cni = {
      before_compute = true
      most_recent    = true
      configuration_values = jsonencode({
        env = {
          ENABLE_POD_ENI                    = "true"
          ENABLE_PREFIX_DELEGATION          = "true"
          POD_SECURITY_GROUP_ENFORCING_MODE = "standard"
        }
        nodeAgent = {
          enablePolicyEventLogs = "true"
        }
        enableNetworkPolicy = "true"
      })
    }
  }
  
  vpc_id          = local.vpc.vpc_id
  subnet_ids      = local.vpc.private_subnets

  create_cluster_security_group = false
  create_node_security_group    = false

  # EKS Managed Node Group(s)

  eks_managed_node_groups = {
    example = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      release_version = "1.29.0-20240129"
      instance_types = ["t3.small"]
      force_update_version = true

      min_size     = 0
      max_size     = 3
      desired_size = 1

      update_config = {
        max_unavailable_percentage = 50
      }

      labels = {
        workshop-default = "yes"
      }      
    }
  }
  
  tags = {
    Environment = "dev"
    Name = "eks-dep-cluster"
  }
}


#############
# Kubernetes
#############

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}



resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = local.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

locals {
  vpc = var.vpc
}


resource "kubernetes_service_account" "eksadmin" {
  metadata {
    name = "eks-admin"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding" "eksadmin" {
  metadata {
    name = "eks-admin"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "eks-admin"
    namespace = "kube-system"
  }
}


resource "kubernetes_service_account" "admineks" {
  metadata {
    name = "admin-eks"
    namespace = "kubernetes-dashboard"
  }
}

resource "kubernetes_cluster_role_binding" "admineks" {
  metadata {
    name = "admin-eks"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "admin-eks"
    namespace = "kubernetes-dashboard"
  }
}

resource "kubernetes_secret" "admineks" {
  metadata {
    name = "admin-eks"
    namespace = "kubernetes-dashboard"
    annotations = {
      "kubernetes.io/service-account.name" = "admin-eks"
    }    
  }
  type = "kubernetes.io/service-account-token"
}

resource "kubernetes_namespace" "airflow" {
  metadata {
    name = "airflow"
  }
}

resource "kubernetes_secret" "airflow_db_credentials" {
  metadata {
    name = "airflow-db-auth"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }

  data = {
    "postgresql-password" = "${var.airflowdb_password}"
  }
}
