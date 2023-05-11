### GENERAL DATA ###

data "aws_availability_zones" "available" {}

variable "private_subnet_cidrs" {
 type        = list(string)
 description = "Private Subnet CIDR values"
 default     = ["10.188.103.0/25", "10.188.103.128/25"]
}

variable "public_subnet_cidrs" {
 type        = list(string)
 description = "Public Subnet CIDR values"
 default     = ["10.188.102.0/25", "10.188.102.128/25"]
}

variable "cluster_name" {
 type    = string
 default = "jenkins-rl"
}

variable "cluster_version" {
 type    = string
 default = "1.24"
}

### NETWORK DEPLOY ###

resource "aws_vpc" "main" {
 cidr_block = "10.188.102.0/23"
 tags = {
  Name = "adhusea11b"
 }
 lifecycle {
  ignore_changes = [
   tags,
  ]
 }
}

resource "aws_subnet" "private_subnets" {
 count             = length(var.private_subnet_cidrs)
 vpc_id            = aws_vpc.main.id
 cidr_block        = element(var.private_subnet_cidrs, count.index)
 availability_zone = element(data.aws_availability_zones.available.names, count.index)
 tags = {
  Name = "internal-${element(data.aws_availability_zones.available.names, count.index)}"
 }
 lifecycle {
  ignore_changes = [
   tags,
  ]
 }
}

resource "aws_subnet" "public_subnets" {
 count             = length(var.public_subnet_cidrs)
 vpc_id            = aws_vpc.main.id
 cidr_block        = element(var.public_subnet_cidrs, count.index)
 availability_zone = element(data.aws_availability_zones.available.names, count.index)
 tags = {
  Name = "internal-${element(data.aws_availability_zones.available.names, count.index)}"
 }
 lifecycle {
  ignore_changes = [
   tags,
  ]
 }
}

### INTERNET ACCESS ###

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw"
  }
}

resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "nat"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name = "nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_route_table_association" "private-subnets" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnets[count.index].id 
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public-subnets" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id 
  route_table_id = aws_route_table.public.id
}

### IAM ROLES AND POLICIES ###

resource "aws_iam_role" "eks-cluster" {
 name = "eks-cluster-${var.cluster_name}"

 path = "/"

 assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Effect": "Allow",
   "Principal": {
    "Service": "eks.amazonaws.com"
   },
   "Action": "sts:AssumeRole"
  }
 ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
 policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
 role    = aws_iam_role.eks-cluster.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly-EKS" {
 policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
 role    = aws_iam_role.eks-cluster.name
}

### NETWORK CONFIG ###

resource "aws_ec2_tag" "vpc" {
 resource_id = aws_vpc.main.id
 key         = "kubernetes.io/cluster/${var.cluster_name}"
 value       = "shared" 
}

resource "aws_ec2_tag" "private_cluster_subnets" {
 count       = length(var.private_subnet_cidrs)
 resource_id = aws_subnet.private_subnets[count.index].id
 key         = "kubernetes.io/cluster/${var.cluster_name}"
 value       = "owned"
}

resource "aws_ec2_tag" "private_nlb_subnets" {
 count       = length(var.private_subnet_cidrs)
 resource_id = aws_subnet.private_subnets[count.index].id
 key         = "kubernetes.io/role/internal-elb"
 value       = "1"
}

resource "aws_ec2_tag" "public_cluster_subnets" {
 count       = length(var.public_subnet_cidrs)
 resource_id = aws_subnet.public_subnets[count.index].id
 key         = "kubernetes.io/cluster/${var.cluster_name}"
 value       = "owned"
}

resource "aws_ec2_tag" "public_nlb_subnets" {
 count       = length(var.public_subnet_cidrs)
 resource_id = aws_subnet.public_subnets[count.index].id
 key         = "kubernetes.io/role/elb"
 value       = "1"
}

resource "aws_iam_role" "workernodes" {
 name = "eks-node-group-${var.cluster_name}"
 assume_role_policy = jsonencode({
  Statement = [{
   Action = "sts:AssumeRole"
   Effect = "Allow"
   Principal = {
    Service = "ec2.amazonaws.com"
   }
  }]
  Version = "2012-10-17"
 })
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
 policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
 role    = aws_iam_role.workernodes.name
}
 
resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
 policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
 role    = aws_iam_role.workernodes.name
}
 
 resource "aws_iam_role_policy_attachment" "EC2InstanceProfileForImageBuilderECRContainerBuilds" {
 policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
 role    = aws_iam_role.workernodes.name
}
 
resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
 policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
 role    = aws_iam_role.workernodes.name
}

### EKS CLUSTER ###

resource "aws_eks_cluster" "eks_cluster" {
 name        = var.cluster_name
 version     = var.cluster_version
 role_arn    = aws_iam_role.eks-cluster.arn
 vpc_config {
  subnet_ids              = flatten([aws_subnet.private_subnets[*].id, aws_subnet.public_subnets[*].id])
  endpoint_private_access = true
 }
 depends_on  = [
  aws_iam_role.eks-cluster
 ]
}

### EKS WORKER NODES ###

resource "aws_eks_node_group" "worker-node-group" {
 cluster_name    = aws_eks_cluster.eks_cluster.name
 node_group_name = "${var.cluster_name}-workernodes"
 node_role_arn   = aws_iam_role.workernodes.arn
 subnet_ids      = aws_subnet.private_subnets[*].id
 instance_types  = ["t3.medium"]
 scaling_config {
  desired_size = 1
  max_size     = 3
  min_size     = 1
 }
 depends_on = [
  aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
  aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
  #aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
 ]
}

### FARGATE PROFILE ###

resource "aws_iam_role" "eks-fargate-profile" {
  name = "eks-fargate-profile"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks-fargate-profile" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.eks-fargate-profile.name
}

resource "aws_eks_fargate_profile" "fg-cardoed5" {
  cluster_name           = aws_eks_cluster.eks_cluster.name
  fargate_profile_name   = "fg-cardoed5"
  pod_execution_role_arn = aws_iam_role.eks-fargate-profile.arn
  subnet_ids             = aws_subnet.private_subnets[*].id
  selector {
    namespace = "fg-cardoed5"
  }
}

resource "helm_release" "nginx" {
  name             = "mywebserver"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "nginx"
  namespace        = "fg-cardoed5"
  create_namespace = true
}

