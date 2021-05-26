terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "3.42.0"
    }
  }
}

provider "aws" {
  region= "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "supreetterraform"
    key    = "fluffy.tfstate"
    region = "us-east-1"
  }
}

resource "aws_vpc" "demo" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "myVPC"
  }
}

variable "PubSubnet"{
  type = list
  default =  ["PublicSubnetA", "PublicSubnetB"]
}

variable "PublicCIDR" {
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "az" {
  default = ["us-east-1a", "us-east-1b"]
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.demo.id
  cidr_block = var.PublicCIDR[count.index]
  availability_zone= var.az[count.index]
  map_public_ip_on_launch = true
  count= 2

  tags = {
    Name = var.PubSubnet[count.index]
  }
}

variable "PvtSubnet" {
  type = list
  default =  ["PrivateSubnetA", "PrivateSubnetB"]
}

variable "PrivateCIDR" {
  default = ["10.0.16.0/20", "10.0.32.0/20"]
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.demo.id
  cidr_block = var.PrivateCIDR[count.index]
  availability_zone= var.az[count.index]
  map_public_ip_on_launch = true
  count= 2

  tags = {
    Name = var.PvtSubnet[count.index]
  }
}

data "aws_ami" "myami" {
  most_recent = true
  owners = ["self"]

  filter {
    name = "name"
    values =["packer-httpd*"]
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow ssh inbound traffic"
  vpc_id      = aws_vpc.demo.id

  ingress {
    description      = "ssh from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["76.67.113.149/32"]
  }

  egress {
    description      = "allow all"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

}

# resource "aws_instance" "myec2" {
#   ami= data.aws_ami.myami.id
#   instance_type = "t2.micro"
#   subnet_id = aws_subnet.public[0].id
#   associate_public_ip_address = true
#   key_name = "key"
#   security_groups = [aws_security_group.allow_ssh.id]
#
#   tags = {
#     Name = "Fluffy"
#   }
# }

resource "aws_internet_gateway" "demoIGW" {
  vpc_id = aws_vpc.demo.id

  tags = {
    Name = "IGW"
  }
}

resource "aws_route_table" "RT" {
  vpc_id = aws_vpc.demo.id

  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.demoIGW.id
    }

  tags = {
   Name = "PublicRT"
 }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.demo.id

  tags = {
   Name = "PvtRT"
 }
}

resource "aws_route_table_association" "A1" {
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.RT.id
}


resource "aws_route_table_association" "B1" {
  subnet_id      = aws_subnet.public[1].id
  route_table_id = aws_route_table.RT.id
}

resource "aws_route_table_association" "A2" {
  subnet_id      = aws_subnet.private[0].id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "B2" {
  subnet_id      = aws_subnet.private[1].id
  route_table_id = aws_route_table.rt.id
}

resource "aws_launch_template" "ASGtemplate" {
  name = "ASGtemplate"
  image_id = data.aws_ami.myami.id
  instance_type = "t2.micro"
  key_name = "key"
#  user_data = base64encode(file("install_nginx.sh"))
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
}

resource "aws_autoscaling_group" "ASG" {
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1
  vpc_zone_identifier  = [aws_subnet.public[0].id, aws_subnet.public[1].id]

  launch_template {
    id      = aws_launch_template.ASGtemplate.id
    version = "$Latest"
  }
}
