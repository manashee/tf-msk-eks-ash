terraform {
  required_version = ">= 0.12.0"
}

provider "aws" {
  version = ">= 2.28.1"
  region  = var.region
}

provider "random" {
  version = "~> 2.1"
}

provider "local" {
  version = "~> 1.2"
}

provider "null" {
  version = "~> 2.1"
}

// The template provider exposes data sources to use templates to generate strings for other Terraform resources or outputs.  

provider "template" {
  version = "~> 2.1"
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

////////////////////////////////////////
// Get an authentication token to communicate with an EKS cluster
// Uses IAM credentials from the AWS provider to generate a temporary token that is compatible with AWS IAM Authenticator authentication. This can be used to authenticate to an EKS cluster or to a cluster that has the AWS IAM Authenticator server configured.
/////////////////////////////////
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

data "aws_caller_identity" "current" {}

provider "kubernetes" {
  version                = "1.10.0"
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

data "aws_availability_zones" "available" {}


// what does locals mean? 
// what should be the name of our cluster? should that not be a constant string? 
// why is he giving a random string as the name of the eks cluster? 

locals {
  cluster_name = "test-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}
  name_prefix = "worker_group_mgmt_one"

resource "aws_security_group" "worker_group_mgmt_one" {
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
  }
      "10.0.0.0/8",
    ]
}
    from_port = 22

resource "aws_security_group" "worker_group_mgmt_two" {
  name_prefix = "worker_group_mgmt_two"
  vpc_id      = module.vpc.vpc_id

  ingress {
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "192.168.0.0/16",
    ]
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  name = "something_interesting"
//  name_prefix = "all_worker_management"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
//      "10.0.0.0/8",
//      "172.16.0.0/12",
//      "192.168.0.0/16",
      "0.0.0.0/0",
    ]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

// enable vp_gateway ? 
// how to 

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.6.0"

  name                 = "vpc-eks"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

// Parametrize asg_desired_capacity, instance_type, asg_max_size, 
// set tags



module "eks" {
  source       = "terraform-aws-modules/eks/aws"
  cluster_name = local.cluster_name
  subnets      = module.vpc.private_subnets

  tags = {
    Environment = "test"
    GithubRepo  = "terraform-aws-eks"
    GithubOrg   = "terraform-aws-modules"
  }

  vpc_id = module.vpc.vpc_id

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t2.micro"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 2
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    },
    {
      name                          = "worker-group-2"
      instance_type                 = "t2.micro"
      additional_userdata           = "echo foo bar"
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_two.id]
      asg_desired_capacity          = 1
    },
  ]

//  worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
//  map_roles                            = var.map_roles
//  map_users                            = var.map_users
//  map_accounts                         = var.map_accounts
}

// Provides a VPC resource.
// what tags should be applied? 


resource "aws_vpc" "vpc" {
  cidr_block = "192.168.0.0/22"
}

data "aws_availability_zones" "azs" {
  state = "available"
}

resource "aws_subnet" "subnet_az1" {
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = "192.168.0.0/24"
  vpc_id            = aws_vpc.vpc.id
}

resource "aws_subnet" "subnet_az2" {
  availability_zone =  data.aws_availability_zones.azs.names[1]
  cidr_block        = "192.168.1.0/24"
  vpc_id            = aws_vpc.vpc.id
}

resource "aws_subnet" "subnet_az3" {
  availability_zone = "${data.aws_availability_zones.azs.names[2]}"
  cidr_block        = "192.168.2.0/24"
  vpc_id            = "${aws_vpc.vpc.id}"
}

resource "aws_security_group" "sg" {
  vpc_id = module.vpc.vpc_id
}


// Provides a KMS customer master key.
resource "aws_kms_key" "kms" {
  description = "example_kms"
}

// How do I parametrize kafka version and cluster name? 

resource "aws_msk_cluster" "example" {
  cluster_name           = "ExampleMSK"
  kafka_version          = "2.2.1"
  number_of_broker_nodes = 2


  broker_node_group_info {
    instance_type  = "kafka.m5.large"
    ebs_volume_size = 8
//    client_subnets = module.vpc.private_subnets
    client_subnets = [
      module.vpc.private_subnets[0],
      module.vpc.private_subnets[1]
    ]
    security_groups = [ aws_security_group.all_worker_mgmt.id ]
  }

  encryption_info {
//    encryption_at_rest_kms_key_arn = "${aws_kms_key.kms.arn}"
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT" # or TLS_PLAINTEXT or PLAINTEXT
    }
  }

  tags = {
    name = "example_multi_az_cluster"
  }
}

// Provides an EC2 key pair resource. A key pair is used to control login access to EC2 instances.
// Currently this resource requires an existing user-supplied key pair. This key pair's public key will be registered with AWS to allow logging-in to EC2 instances.
// where is local.pub?
// where is local (private key)?

resource "aws_key_pair" "auth" {
  key_name   = "ExampleMSK"
  public_key = file("local.pub")
}


//Provides an EC2 instance resource. This allows instances to be created, updated, and deleted. 
// to run the schema?

// how do I parametrize the ami, instance type?
// what tag should be set? 
// which subnet should the schema instance be launched in ? 

// The remote-exec provisioner invokes a script on a remote resource after it is created. This can be used to run a configuration management tool, bootstrap into a cluster, etc. 

resource "aws_instance" "schema" {
  ami = "ami-0121a97ac334cb2cf"
  tags = {
    Name = "schema"
  }
  instance_type = "t2.small"
  subnet_id = module.vpc.public_subnets[0]
  vpc_security_group_ids = [ aws_security_group.all_worker_mgmt.id ]

  user_data = templatefile("registry.sh.tpl", {
    zoo_keeper = aws_msk_cluster.example.zookeeper_connect_string
    broker_list = aws_msk_cluster.example.bootstrap_brokers
  })
  
  key_name = "ExampleMSK"
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "ec2-user"
      private_key = file("local")
      host     = aws_instance.schema.public_ip
    }

    inline = [
      "confluent-5.3.1/bin/schema-registry-start confluent-5.3.1/etc/schema-registry/schema-registry.properties &> /dev/null &",
    ]
  }
}



//Provides an EC2 instance resource. This allows instances to be created, updated, and deleted. 
// to run the producer?

resource "aws_instance" "producer" {
  ami = "ami-0121a97ac334cb2cf"
  tags = {
    Name = "producer"
  }
  instance_type = "t2.small"
  subnet_id = module.vpc.public_subnets[0]
  vpc_security_group_ids = [ aws_security_group.all_worker_mgmt.id ]
  user_data = templatefile("produce.sh.tpl", {
    zoo_keeper = aws_msk_cluster.example.zookeeper_connect_string
    broker_list = aws_msk_cluster.example.bootstrap_brokers
  })
  key_name = "ExampleMSK"
  provisioner "file" {
    connection {
      type     = "ssh"
      user     = "ec2-user"
      private_key = file("local")
      host     = aws_instance.producer.public_ip
    }

    content      = templatefile("producerscript.sh.tpl", {
      zoo_keeper = aws_msk_cluster.example.zookeeper_connect_string
      broker_list = aws_msk_cluster.example.bootstrap_brokers
    })
    destination = "~/script.sh"
  }
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "ec2-user"
      private_key = file("local")
      host     = aws_instance.producer.public_ip
    }

    inline = [
      "sudo chmod +x ~/script.sh"
//      "~/script.sh"
    ]
  }
}

//Provides an EC2 instance resource. This allows instances to be created, updated, and deleted. 
// to run the consumer?


resource "aws_instance" "consumer" {
  ami = "ami-0121a97ac334cb2cf"
  tags = {
    Name = "consumer"
  }
//  key_name = "Yubico ssh"
  instance_type = "t2.small"
  subnet_id = module.vpc.public_subnets[0]
  vpc_security_group_ids = [ aws_security_group.all_worker_mgmt.id ]
  user_data = templatefile("consumer.sh.tpl", {
    zoo_keeper = aws_msk_cluster.example.zookeeper_connect_string
    broker_list = aws_msk_cluster.example.bootstrap_brokers
  })
  key_name = "ExampleMSK"
  provisioner "file" {
    connection {
      type     = "ssh"
      user     = "ec2-user"
      private_key = file("local")
      host     = aws_instance.consumer.public_ip
    }

    content      = templatefile("consumerscript.sh.tpl", {
      zoo_keeper = aws_msk_cluster.example.zookeeper_connect_string
      broker_list = aws_msk_cluster.example.bootstrap_brokers
    })
    destination = "~/script.sh"
  }
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "ec2-user"
      private_key = file("local")
      host     = aws_instance.consumer.public_ip
    }

    inline = [
      "chmod +x ~/script.sh"
//      "~/script.sh"
    ]
  }
}