# SG za EC2 instance
resource "aws_security_group" "ec2" {
  name        = "social-medias-ec2-sg"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "social-medias-ec2-sg"
  }
}

#Superset web UI
resource "aws_vpc_security_group_ingress_rule" "ec2_superset_ui" {
  for_each          = toset(var.allowed_cidrs)
  security_group_id = aws_security_group.ec2.id
  description       = "Apache Superset web UI"
  cidr_ipv4         = each.value
  from_port         = 8088
  to_port           = 8088
  ip_protocol       = "tcp"
}

# SSH
resource "aws_vpc_security_group_ingress_rule" "ec2_ssh" {
  for_each          = toset(var.allowed_cidrs)
  security_group_id = aws_security_group.ec2.id
  description       = "SSH administracija"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# PostgreSQL
resource "aws_vpc_security_group_ingress_rule" "ec2_postgres_from_lambda" {
  security_group_id            = aws_security_group.ec2.id
  referenced_security_group_id = aws_security_group.lambda.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# HTTPS
resource "aws_vpc_security_group_egress_rule" "ec2_https_out" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# HTTP
resource "aws_vpc_security_group_egress_rule" "ec2_http_out" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# DNS
resource "aws_vpc_security_group_egress_rule" "ec2_dns_udp" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "ec2_dns_tcp" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
}

# SG za Lambda funkcije
resource "aws_security_group" "lambda" {
  name        = "social-medias-lambda-sg"
  description = "Odlazni saobracaj Lambdi: Postgres ka EC2 i HTTPS ka S3/HN API"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "social-medias-lambda-sg"
  }
}

# PostgreSQL
resource "aws_vpc_security_group_egress_rule" "lambda_to_postgres" {
  security_group_id            = aws_security_group.lambda.id
  referenced_security_group_id = aws_security_group.ec2.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# HTTPS ka S3
resource "aws_vpc_security_group_egress_rule" "lambda_https_out" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS ka S3"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# DNS
resource "aws_vpc_security_group_egress_rule" "lambda_dns_udp" {
  security_group_id = aws_security_group.lambda.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "lambda_dns_tcp" {
  security_group_id = aws_security_group.lambda.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
}
