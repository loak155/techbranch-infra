#--------------------------------------------------------------
# Variables
#--------------------------------------------------------------

variable "domain" {
  type = string
}

#--------------------------------------------------------------
# Route53 Hosted Zone
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone.html
data "aws_route53_zone" "this" {
  name         = var.domain
  private_zone = false
}

#--------------------------------------------------------------
#  AWS Certificate Manager
# 検証方法をDNSでACM証明書をリクエストする
#--------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  domain_name = var.domain

  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

#--------------------------------------------------------------
# Route53 record
# ホストゾーンに検証用のレコードを作成する
#--------------------------------------------------------------

# https://www.terraform.io/docs/providers/aws/r/route53_record.html
# サブドメインとルートドメインのホストゾーンを関連付ける
# ルートドメインのホストゾーンにサブドメインのホストゾーン割り当てられる４つのネームサーバをNSレコードとして登録する
resource "aws_route53_record" "this" {
  depends_on = [aws_acm_certificate.this]

  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.this.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
}

#--------------------------------------------------------------
# ACM Validate
# 作成したACM証明書と作成した検証用レコードのCNAMEレコードの連携する
#--------------------------------------------------------------

# https://www.terraform.io/docs/providers/aws/r/acm_certificate_validation.html
resource "aws_acm_certificate_validation" "this" {
  certificate_arn = aws_acm_certificate.this.arn

  validation_record_fqdns = [for record in aws_route53_record.this : record.fqdn]
}

#--------------------------------------------------------------
# Output
#--------------------------------------------------------------

output "acm_id" {
  value = aws_acm_certificate.this.id
}
