module "network" {
 source = "../network"
}

resource "aws_iam_role" "eks-iam-role" {
 name = "devopsthehardway-eks-iam-role"

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
 role    = aws_iam_role.eks-iam-role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly-EKS" {
 policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
 role    = aws_iam_role.eks-iam-role.name
}

resource "aws_eks_cluster" "jenkins-rl" {
 name = "jenkins-rl"
 role_arn = aws_iam_role.eks-iam-role.arn
 vpc_config {
  subnet_ids = [var.subnet_id_1, var.subnet_id_2]
 }
 depends_on = [
  aws_iam_role.eks-iam-role,
 ]
}

resource "aws_ec2_tag" "vpc" {
 resource_id = local.vpc_id
 key         = "kubernetes.io/cluster/${var.cluster_name}"
 value       = "shared" 
}

