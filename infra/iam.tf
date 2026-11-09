data "aws_caller_identity" "current" {}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_instance_role" {
  name               = "${var.project_name}-${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ecr_pull" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPull"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [aws_ecr_repository.api.arn, aws_ecr_repository.web.arn]
  }
}

resource "aws_iam_role_policy" "ecr_pull" {
  name   = "${var.project_name}-${var.environment}-ecr-pull"
  role   = aws_iam_role.ec2_instance_role.id
  policy = data.aws_iam_policy_document.ecr_pull.json
}

data "aws_iam_policy_document" "ssm_read" {
  statement {
    sid    = "SsmReadAppParams"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/${var.environment}/*",
    ]
  }

  statement {
    sid       = "SsmKmsDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]
  }
}

resource "aws_iam_role_policy" "ssm_read" {
  name   = "${var.project_name}-${var.environment}-ssm-read"
  role   = aws_iam_role.ec2_instance_role.id
  policy = data.aws_iam_policy_document.ssm_read.json
}

# Le o manifesto de deploy que o CI sobe no S3 (evita embutir o payload
# inline no comando do SSM, que travava com o manifesto+Secret > ~10KB).
data "aws_iam_policy_document" "deploy_manifest_read" {
  statement {
    sid       = "DeployManifestGet"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::mechanicltda-terraform-state-788516091173/deploy/*"]
  }
}

resource "aws_iam_role_policy" "deploy_manifest_read" {
  name   = "${var.project_name}-${var.environment}-deploy-manifest-read"
  role   = aws_iam_role.ec2_instance_role.id
  policy = data.aws_iam_policy_document.deploy_manifest_read.json
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_instance_role.name
}

# Permite ao server publicar o join-token do k3s no SSM para os workers do
# ASG lerem no boot. Escopado só a esse parâmetro, não ao prefixo inteiro.
data "aws_iam_policy_document" "ssm_write_node_token" {
  statement {
    sid       = "SsmPutNodeToken"
    effect    = "Allow"
    actions   = ["ssm:PutParameter"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_path_prefix}/k3s-node-token"]
  }

  # Escrever um SecureString exige encrypt, não só decrypt — a policy de
  # leitura acima (ssm_read) não cobre isso.
  statement {
    sid       = "SsmKmsEncryptForNodeToken"
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]
  }
}

resource "aws_iam_role_policy" "ssm_write_node_token" {
  name   = "${var.project_name}-${var.environment}-ssm-write-node-token"
  role   = aws_iam_role.ec2_instance_role.id
  policy = data.aws_iam_policy_document.ssm_write_node_token.json
}

# ── Workers k3s (ASG) ────────────────────────────────────────────────────

resource "aws_iam_role" "worker_instance_role" {
  name               = "${var.project_name}-${var.environment}-worker-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "worker_ssm_read_token" {
  statement {
    sid       = "SsmReadNodeToken"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_path_prefix}/k3s-node-token"]
  }

  statement {
    sid       = "SsmKmsDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]
  }
}

# Descoberta do server k3s pela tag Name no boot (user_data_worker.sh.tpl).
data "aws_iam_policy_document" "worker_describe_server" {
  statement {
    sid       = "DescribeInstances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "worker_describe_server" {
  name   = "${var.project_name}-${var.environment}-worker-describe-server"
  role   = aws_iam_role.worker_instance_role.id
  policy = data.aws_iam_policy_document.worker_describe_server.json
}

resource "aws_iam_role_policy" "worker_ssm_read_token" {
  name   = "${var.project_name}-${var.environment}-worker-ssm-read-token"
  role   = aws_iam_role.worker_instance_role.id
  policy = data.aws_iam_policy_document.worker_ssm_read_token.json
}

resource "aws_iam_role_policy_attachment" "worker_ssm_core" {
  role       = aws_iam_role.worker_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.project_name}-${var.environment}-worker-profile"
  role = aws_iam_role.worker_instance_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Acesso via SSM Session Manager (sem SSH/porta 22 aberta).
# IAM clássico, não Identity Center: Permission Sets/Account Assignments só
# são suportados em Organization instances do Identity Center, não na Account
# instance usada aqui (confirmado por erro real da API: "This operation is
# not supported for account instances of IAM Identity Center").

data "aws_iam_policy_document" "ssm_session_access" {
  statement {
    sid       = "StartSession"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = [aws_instance.app.arn]
  }

  statement {
    sid       = "SessionSelfManage"
    effect    = "Allow"
    actions   = ["ssm:TerminateSession", "ssm:ResumeSession"]
    resources = ["arn:aws:ssm:*:*:session/$${aws:userid}-*"]
  }

  statement {
    sid       = "SessionDescribe"
    effect    = "Allow"
    actions   = ["ssm:DescribeSessions", "ssm:GetConnectionStatus", "ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_group" "ssm_users" {
  name = "${var.project_name}-${var.environment}-ssm-users"
}

resource "aws_iam_group_policy" "ssm_session" {
  name   = "${var.project_name}-${var.environment}-ssm-session"
  group  = aws_iam_group.ssm_users.name
  policy = data.aws_iam_policy_document.ssm_session_access.json
}

# Permite ao terraform-deployer usar EC2 Instance Connect para debug direto
# via SSH, sem depender do key pair original (perdido) nem do SSM (que
# ainda nao registrou a instancia - motivo desta propria investigacao).
data "aws_iam_policy_document" "ec2_instance_connect" {
  statement {
    sid       = "SendSshPublicKey"
    effect    = "Allow"
    actions   = ["ec2-instance-connect:SendSSHPublicKey"]
    resources = [aws_instance.app.arn]
  }
}

resource "aws_iam_user_policy" "ec2_instance_connect" {
  name   = "${var.project_name}-instance-connect-debug"
  user   = "terraform-deployer"
  policy = data.aws_iam_policy_document.ec2_instance_connect.json
}
