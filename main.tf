
provider "aws" {
  region = "us-west-2"
}




# chave para acesso aos ec2
resource "tls_private_key" "public_key_gen" {
  algorithm = "RSA"
}

resource "aws_key_pair" "key_generation" {
  key_name   = "task_key"
  public_key = tls_private_key.public_key_gen.public_key_openssh
  depends_on = [tls_private_key.public_key_gen]
}

resource "local_file" "private_key" {
  content  = tls_private_key.public_key_gen.private_key_pem
  filename = "private_key.pem"

  provisioner "local-exec" {
    command = "chmod 600 private_key.pem"
  }

}


# Default VPC
resource "aws_vpc" "template_default_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"

  tags = {
    Name = "template-default-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.template_default_vpc.id
}

# Public Subnet
resource "aws_subnet" "template_public_subnet_a" {
  vpc_id                  = aws_vpc.template_default_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "template-public-subnet-a"
  }
}

# Default Security Group for Load Balancer
resource "aws_security_group" "template_default_lb" {
  name        = "template-default-lb"
  description = "template-default-lb"
  vpc_id      = aws_vpc.template_default_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # make this your IP/IP Range
  }

  ingress {
    description = "CONSUL"
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # make this your IP/IP Range
  }

  ingress {
    description = "PROMETHEUS"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # make this your IP/IP Range
  }
  ingress {
    description = "grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # make this your IP/IP Range
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "REDE PRIVADA"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.1.0/24"]
  }
  
  egress {
    description = "ALL"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "template-default-lb"
  }
}

resource "aws_default_route_table" "rtb-default" {
  default_route_table_id = aws_vpc.template_default_vpc.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}


# ec2 nginx
resource "aws_instance" "nginx" {
  count           = 1
  ami             = "ami-0cf6f564e6d7c44b0"
  instance_type   = "t2.micro"
  monitoring      = true
  key_name        = aws_key_pair.key_generation.key_name
  subnet_id                   = aws_subnet.template_public_subnet_a.id
  private_ip                  = "10.0.1.10"
  vpc_security_group_ids      = [aws_security_group.template_default_lb.id]
  associate_public_ip_address = true
  tags = {
    Name = "Nginx_${count.index}"
  }
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '${self.public_ip},' --private-key private_key.pem -e 'IP=${self.public_ip}' ansible_terraform_nginx.yml"
  }
}

# ec2 prometheus/grafana
resource "aws_instance" "monitor" {
  count           = 1
  ami             = "ami-0b88eb1b79cbc39a6"
  instance_type   = "t2.micro"
  monitoring      = true
  key_name        = aws_key_pair.key_generation.key_name
  subnet_id                   = aws_subnet.template_public_subnet_a.id
  vpc_security_group_ids      = [aws_security_group.template_default_lb.id]
  associate_public_ip_address = true
  tags = {
    Name = "Monitor_${count.index}"
  }
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '${self.public_ip},' --private-key private_key.pem -e 'IP=${self.public_ip} IP_PRIVATE=${aws_instance.nginx.0.private_ip}' ansible_terraform_monitor.yml"
  }
}

# ec2 apache
resource "aws_instance" "apache" {
  count           = 3
  ami             = "ami-00014e260618eb760"
  instance_type   = "t2.micro"
  monitoring      = true
  key_name        = aws_key_pair.key_generation.key_name
  subnet_id                   = aws_subnet.template_public_subnet_a.id
  vpc_security_group_ids      = [aws_security_group.template_default_lb.id]
  associate_public_ip_address = true
  tags = {
    Name = "Apache_${count.index}"
  }
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '${self.public_ip},' --private-key private_key.pem --extra-vars 'IP=${self.public_ip} IP_PRIVATE=${aws_instance.nginx.0.private_ip}' ansible_terraform_apache.yml"
  }
}





