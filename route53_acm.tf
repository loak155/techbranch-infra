####################################################
# Route53 Host Zone
####################################################
data aws_route53_zone host_domain {
  name = local.host_domain
}

resource "aws_route53_zone" "app_subdomain" {
  name = local.app_domain_name
}

resource "aws_route53_zone" "api_subdomain" {
  name = local.api_domain_name
}

####################################################
# Create NS record
####################################################

resource "aws_route53_record" "ns_record_for_app_subdomain" {
  name    = aws_route53_zone.app_subdomain.name
  type    = "NS"
  zone_id = data.aws_route53_zone.host_domain.id
  records = [
    aws_route53_zone.app_subdomain.name_servers[0],
    aws_route53_zone.app_subdomain.name_servers[1],
    aws_route53_zone.app_subdomain.name_servers[2],
    aws_route53_zone.app_subdomain.name_servers[3],
  ]
  ttl = 86400
}

resource "aws_route53_record" "ns_record_for_api_subdomain" {
  name    = aws_route53_zone.api_subdomain.name
  type    = "NS"
  zone_id = data.aws_route53_zone.host_domain.id
  records = [
    aws_route53_zone.api_subdomain.name_servers[0],
    aws_route53_zone.api_subdomain.name_servers[1],
    aws_route53_zone.api_subdomain.name_servers[2],
    aws_route53_zone.api_subdomain.name_servers[3],
  ]
  ttl = 86400
}

####################################################
# Import Host domain Wildcard ACM
####################################################

resource "aws_acm_certificate" "host_domain_wc_acm" {
  domain_name       = data.aws_route53_zone.host_domain.name
  subject_alternative_names = ["*.${local.host_domain}"]
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "host_domain_wc_acm_dns_verify" {
  for_each = {
    for dvo in aws_acm_certificate.host_domain_wc_acm.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
  zone_id = data.aws_route53_zone.host_domain.id
}

resource "aws_acm_certificate_validation" "host_domain_wc_acm" {
  certificate_arn         = aws_acm_certificate.host_domain_wc_acm.arn
  validation_record_fqdns = [for record in aws_route53_record.host_domain_wc_acm_dns_verify : record.fqdn]
}