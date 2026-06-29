data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "viz" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_name != "" ? var.key_name : null

  # bootstrap skripta - Terraform ubacuje lozinke i kljuceve pre slanja
  user_data = templatefile("${path.module}/templates/userdata.sh.tpl", {
    db_user                  = var.db_user
    db_password              = var.db_password
    superset_secret_key      = var.superset_secret_key
    superset_admin_password  = var.superset_admin_password
  })

  # ako se promeni bootstrap skripta zameni instancu
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20 # GB - dovoljno za docker image i podatke
    volume_type = "gp3"
  }

  tags = {
    Name      = "social-medias-superset"
    Project   = "big-data"
    ManagedBy = "Terraform"
  }
}
