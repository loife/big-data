# Dohvata dostupne Availability Zone u regionu
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16" # 65k privatnih IP adresa
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "social-medias-vpc"
    Project   = "big-data"
    ManagedBy = "Terraform"
  }
}

# public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true # EC2 automatski dobija javnu IP

  tags = {
    Name = "social-medias-public"
  }
}

# private subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "social-medias-private"
  }
}

# gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "social-medias-igw"
  }
}

# javna ruta - sav traffic ide kroz gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "social-medias-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# privatna ruta - traffic ka S3 dodaje automatski S3 Gateway Endpoint
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "social-medias-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# S3 Gateway Endpoint - traffic ka S3 ide privatno kroz AWS backbone
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id] # automatski dodaje rutu ka S3 u privatnu tabelu

  tags = {
    Name = "social-medias-s3-endpoint"
  }
}
