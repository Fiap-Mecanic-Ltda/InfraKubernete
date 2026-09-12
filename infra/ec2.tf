data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  # "al2023-ami-*-x86_64" também casa com a variante "minimal", que não vem
  # com o SSM Agent nem o EC2 Instance Connect pré-instalados (confirmado:
  # essa variante foi selecionada e nenhum dos dois funcionava na instância).
  # "al2023-ami-2*-x86_64" pega só a variante padrão (nome começa com o ano).
  filter {
    name   = "name"
    values = ["al2023-ami-2*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_eip" "app" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-eip"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id, aws_security_group.k3s_mesh.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.ec2_key_pair_name

  # IP público necessário por design: não há NAT Gateway (custo) nem Load Balancer
  # nesta arquitetura de instância única, então é o próprio IP público que dá à EC2
  # saída para a internet (pull de imagem do ECR, agente SSM) e também é o que
  # expõe a API/Web publicamente na porta 8080/8090 (Swagger, consumo externo das
  # APIs e demo em vídeo são requisitos do desafio). A superfície exposta é
  # limitada pelo security group (aws_security_group.ec2, em security_groups.tf),
  # que restringe as portas liberadas via var.api_allowed_cidr — não é um
  # "0.0.0.0/0 em tudo" por acidente.
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  # user_data só instala o k3s e o timer de refresh das credenciais do ECR —
  # o deploy da aplicação (ConfigMap/Secret/Deployments) é feito pela pipeline
  # de CI/CD via SSM Run Command, não no boot da instância.
  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    region            = var.aws_region
    ecr_registry_host = split("/", aws_ecr_repository.api.repository_url)[0]
    token_param_name  = "${local.ssm_path_prefix}/k3s-node-token"
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-api"
  }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}
