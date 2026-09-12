resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-${var.environment}-ec2-sg"
  description = "SG da instancia EC2 que roda a API"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "API HTTP (NodePort k3s)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.api_allowed_cidr]
  }

  ingress {
    description = "Web HTTP (NodePort k3s)"
    from_port   = 8090
    to_port     = 8090
    protocol    = "tcp"
    cidr_blocks = [var.api_allowed_cidr]
  }

  # TEMPORÁRIO: SSH liberado só para investigar por que o amazon-ssm-agent
  # não está registrando (user_data falhou baixando o k3s por erro de TLS).
  # Remover depois de diagnosticar.
  ingress {
    description = "SSH temporario para debug (remover depois)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["177.140.244.92/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-sg"
  }
}

# O security group do RDS foi para o repositorio de infra do banco gerenciado:
# e la que ele e criado, liberando a 1433 para os SGs dos nos k3s (ec2 e worker),
# cujos ids sao lidos deste stack via terraform_remote_state.

resource "aws_security_group" "k3s_mesh" {
  name        = "${var.project_name}-${var.environment}-k3s-mesh-sg"
  description = "SG compartilhado entre o server e os workers k3s (API, kubelet, flannel VXLAN)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "k3s API (agent para server)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Flannel VXLAN (overlay entre nos)"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  ingress {
    description = "Kubelet API (kubectl exec/logs, scrape do metrics-server)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-k3s-mesh-sg"
  }
}

resource "aws_security_group" "worker" {
  name        = "${var.project_name}-${var.environment}-worker-sg"
  description = "SG base dos workers k3s (ingress entre nos vem do k3s_mesh)"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-worker-sg"
  }
}
