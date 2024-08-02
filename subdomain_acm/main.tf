#--------------------------------------------------------------
# Variables
#--------------------------------------------------------------

variable "domain" {
  type = string
}

variable "subdomain" {
  type = string
}

#--------------------------------------------------------------
# Route53 Hosted Zone
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone.html
data "aws_route53_zone" "domain" {
  name         = var.domain
  private_zone = false
}

resource "aws_route53_zone" "subdomain" {
  name = var.subdomain
}

#--------------------------------------------------------------
#  AWS Certificate Manager
# 検証方法をDNSでACM証明書をリクエストする
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate
resource "aws_acm_certificate" "this" {
  domain_name               = data.aws_route53_zone.domain.name
  # ルートドメイン、サブドメインすべてをHTTPS化するため、
  # subject_alternative_namesでワイルドカードを使用し、サブドメインも含んだSSL証明書を発行する
  subject_alternative_names = [format("*.%s", data.aws_route53_zone.domain.name)]
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
resource "aws_route53_record" "ns_record_for_subdomain" {
  name    = aws_route53_zone.subdomain.name
  zone_id = data.aws_route53_zone.domain.id
  records = [
    aws_route53_zone.subdomain.name_servers[0],
    aws_route53_zone.subdomain.name_servers[1],
    aws_route53_zone.subdomain.name_servers[2],
    aws_route53_zone.subdomain.name_servers[3]
  ]
  ttl  = 172800
  type = "NS"
}

# 証明書の検証につかうレコードを作成する
resource "aws_route53_record" "certificate" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.domain.id
  allow_overwrite = true
}

#--------------------------------------------------------------
# ACM Validate
# 作成したACM証明書と作成した検証用レコードのCNAMEレコードの連携する
#--------------------------------------------------------------

# https://www.terraform.io/docs/providers/aws/r/acm_certificate_validation.html
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate : record.fqdn]
}

#--------------------------------------------------------------
# Output
#--------------------------------------------------------------

output "acm_id" {
  value = aws_acm_certificate.this.id
}

output "subdomain_zone_id" {
  value = aws_route53_zone.subdomain.id
}





