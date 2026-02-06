provider "aws" {
  region = "us-east-1"
}

###############################
# 1. Shared Key Pair
###############################
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "shared_key" {
  key_name   = "my-keypair"
  public_key = tls_private_key.example.public_key_openssh
}

resource "local_file" "private_key_pem" {
  content         = tls_private_key.example.private_key_pem
  filename        = "${path.module}/my-keypair.pem"
  file_permission = "0600"
}

###############################
# 1a. S3 Bucket for flows
###############################
resource "random_integer" "suffix" {
  min = 100000
  max = 999999
}

resource "aws_s3_bucket" "illumio_flows" {
  bucket        = "illumios3bucketforflows${random_integer.suffix.result}"
  force_destroy = true

  tags = {
    Name    = "illumios3bucketforflows"
    company = "illumio"
  }
}

###############################
# 2. Locals
###############################
locals {
  ec2_instances = {
    "monitoring-staging-nagios" = {
      app        = "monitoring"
      env        = "staging"
      role       = "nagios"
      compliance = "medium"
    },
    "finance-dev-db" = {
      app        = "finance"
      env        = "dev"
      role       = "db"
      compliance = "low"
    },
    "crm-dev-counter" = {
      app        = "crm"
      env        = "dev"
      role       = "counter"
      compliance = "low"
    },
    "finance-prod-web" = {
      app        = "finance"
      env        = "prod"
      role       = "web"
      compliance = "high"
    },
    "finance-prod-processing" = {
      app        = "finance"
      env        = "prod"
      role       = "processing"
      compliance = "high"
    },
    "finance-prod-db" = {
      app        = "finance"
      env        = "prod"
      role       = "db"
      compliance = "high"
    },
    "crm-prod-counter" = {
      app        = "crm"
      env        = "prod"
      role       = "counter"
      compliance = "high"
    }
  }

  subnet_map = {
    dev     = aws_subnet.dev_subnet.id
    staging = aws_subnet.staging_subnet.id
    prod    = aws_subnet.prod_subnet.id
  }

  security_group_map = {
    nagios     = aws_security_group.nagios_sg.id
    web        = aws_security_group.web_sg.id
    db         = aws_security_group.db_sg.id
    processing = aws_security_group.processing_sg.id
    counter    = aws_security_group.counter_sg.id
  }

  private_ip_map = {
    "monitoring-staging-nagios" = "10.0.2.50"
    "finance-dev-db"           = "10.0.1.30"
    "crm-dev-counter"          = "10.0.1.40"
    "finance-prod-web"         = "10.0.3.10"
    "finance-prod-processing"  = "10.0.3.20"
    "finance-prod-db"          = "10.0.3.30"
    "crm-prod-counter"         = "10.0.3.40"
  }
}

###############################
# 3. Networking
###############################
resource "aws_vpc" "illumio_lab" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name    = "illumio_lab"
    company = "illumio"
  }
}

resource "aws_subnet" "dev_subnet" {
  vpc_id                  = aws_vpc.illumio_lab.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "dev_subnet"
    env     = "dev"
    company = "illumio"
  }
}

resource "aws_subnet" "staging_subnet" {
  vpc_id                  = aws_vpc.illumio_lab.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "staging_subnet"
    env     = "staging"
    company = "illumio"
  }
}

resource "aws_subnet" "prod_subnet" {
  vpc_id                  = aws_vpc.illumio_lab.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "prod_subnet"
    env     = "prod"
    company = "illumio"
  }
}

resource "aws_internet_gateway" "lab_ig" {
  vpc_id = aws_vpc.illumio_lab.id

  tags = {
    Name    = "lab_ig"
    company = "illumio"
  }
}

resource "aws_route_table" "dev_rt" {
  vpc_id = aws_vpc.illumio_lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_ig.id
  }

  tags = {
    Name    = "rt_dev"
    env     = "dev"
    company = "illumio"
  }
}

resource "aws_route_table" "staging_rt" {
  vpc_id = aws_vpc.illumio_lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_ig.id
  }

  tags = {
    Name    = "rt_staging"
    env     = "staging"
    company = "illumio"
  }
}

resource "aws_route_table" "prod_rt" {
  vpc_id = aws_vpc.illumio_lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_ig.id
  }

  tags = {
    Name    = "rt_prod"
    env     = "prod"
    company = "illumio"
  }
}

resource "aws_route_table_association" "dev_assoc" {
  subnet_id      = aws_subnet.dev_subnet.id
  route_table_id = aws_route_table.dev_rt.id
}

resource "aws_route_table_association" "staging_assoc" {
  subnet_id      = aws_subnet.staging_subnet.id
  route_table_id = aws_route_table.staging_rt.id
}

resource "aws_route_table_association" "prod_assoc" {
  subnet_id      = aws_subnet.prod_subnet.id
  route_table_id = aws_route_table.prod_rt.id
}

###############################
# 4. Security Groups (per role, SSH only)
###############################
resource "aws_security_group" "nagios_sg" {
  name   = "nagios_sg"
  vpc_id = aws_vpc.illumio_lab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "nagios_sg"
    role    = "nagios"
    company = "illumio"
  }
}

resource "aws_security_group" "web_sg" {
  name   = "web_sg"
  vpc_id = aws_vpc.illumio_lab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "web_sg"
    role    = "web"
    company = "illumio"
  }
}

resource "aws_security_group" "db_sg" {
  name   = "db_sg"
  vpc_id = aws_vpc.illumio_lab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "db_sg"
    role    = "db"
    company = "illumio"
  }
}

resource "aws_security_group" "processing_sg" {
  name   = "processing_sg"
  vpc_id = aws_vpc.illumio_lab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "processing_sg"
    role    = "processing"
    company = "illumio"
  }
}

resource "aws_security_group" "counter_sg" {
  name   = "counter_sg"
  vpc_id = aws_vpc.illumio_lab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "counter_sg"
    role    = "counter"
    company = "illumio"
  }
}

###############################
# 5. AMI (UPDATED: Amazon Linux 2023 for t3a.nano)
###############################
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

###############################
# 6. EC2 Instances (static IPs)
###############################
resource "aws_instance" "ec2" {
  for_each = local.ec2_instances

  ami           = data.aws_ssm_parameter.ami.value
  instance_type = "t3a.nano"
  subnet_id     = local.subnet_map[each.value.env]

  private_ip = lookup(local.private_ip_map, each.key)

  vpc_security_group_ids = [
    local.security_group_map[each.value.role]
  ]

  key_name = aws_key_pair.shared_key.key_name

  tags = {
    Name       = each.key
    app        = each.value.app
    env        = each.value.env
    role       = each.value.role
    compliance = each.value.compliance
    company    = "illumio"
  }
}
