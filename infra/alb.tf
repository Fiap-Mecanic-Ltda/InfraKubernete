# ALB interno: a porta de entrada privada do cluster.
#
# O API Gateway (repositório Lambda) chega até aqui por VPC Link, e o ALB
# distribui para o NodePort 8080 de qualquer nó do k3s — o server ou um worker
# do ASG. É interno de propósito: com ele no lugar, o único caminho público para
# a aplicação passa a ser o API Gateway, que dá HTTPS, autenticação e throttling.

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "SG do ALB interno que recebe o trafego do API Gateway (VPC Link)"
  vpc_id      = aws_vpc.main.id

  # A entrada vem das ENIs do VPC Link, que ficam nas sub-redes de aplicação.
  # A origem é o CIDR dessas sub-redes, e não o security group do VPC Link,
  # porque aquele SG é criado no stack da Lambda — referenciá-lo aqui criaria
  # dependência circular entre os dois stacks.
  ingress {
    description = "HTTP do VPC Link do API Gateway"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.app_subnet_a_cidr, var.app_subnet_b_cidr]
  }

  egress {
    description = "NodePort dos nos k3s na sub-rede publica"
    from_port   = 8080
    to_port     = 8090
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

# Sem access_logs de propósito (terraform:S6258, aceito no Sonar). O ALB é
# interno e só recebe tráfego do VPC Link, e cada requisição já fica registrada
# no access log do API Gateway (CloudWatch, repositório Lambda) com o requestId
# que chega à API no header X-Correlation-Id e entra nos logs e traces do New
# Relic. Os access logs do ALB só podem ir para S3, o que exigiria buckets
# dedicados para repetir a mesma informação.
resource "aws_lb" "internal" {
  name               = "${var.project_name}-${var.environment}-int-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.app_a.id, aws_subnet.app_b.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-int-alb"
  }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.project_name}-${var.environment}-api-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  # /health é anônimo na API e responde 200 quando o pod está pronto. Como o
  # alvo é o NodePort, qualquer nó saudável serve qualquer pod da API.
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # Os pods entram e saem com o HPA; esperar os 300 s padrão só atrasaria o
  # rollout sem ganho nenhum para requisições curtas de API.
  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-api-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  # TLS termina no API Gateway. Aqui o tráfego é HTTP dentro da VPC — não há
  # certificado para um hostname interno, e o salto não sai da rede privada.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# O server do k3s também executa pods da API. Os workers entram no target group
# pelo próprio ASG (ver asg.tf), então não aparecem aqui.
resource "aws_lb_target_group_attachment" "server" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.app.id
  port             = 8080
}
