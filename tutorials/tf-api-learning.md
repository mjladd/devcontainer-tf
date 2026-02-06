<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# Walk through a specific example for someone writing terraform code using these methods.

Take a very concrete flow: a junior is writing Terraform that must call an internal REST API to discover the latest AMI, then use that AMI in an `aws_instance`. We’ll walk it end‑to‑end using docs, an API client, and then Terraform.

***

## 1. Understand the API from docs

You first sit them down with the API’s documentation (or OpenAPI spec) and have them answer, in words, before touching Terraform:

- What is the URL? e.g. `https://ami-registry.internal/api/v1/amis/latest`.
- What auth is required? e.g. header `X-API-Key: <key>`.
- What does the response JSON look like? e.g.:

```json
{
  "ami_id": "ami-0123456789abcdef0",
  "version": "2026.01.01",
  "build_date": "2026-01-01"
}
```

If the docs provide examples, they copy one into a note and annotate which fields they actually care about (here: `ami_id`, `version`, `build_date`).[^1][^2]

Key lesson: the spec/doc is the contract; Terraform is just one consumer of that contract.

***

## 2. Probe the API in a client

Before Terraform, they use an API client (Postman/Insomnia/Hoppscotch) or `curl` to make sure they really understand how the API behaves.[^3][^4]

Example with `curl`:

```bash
curl -s \
  -H "Accept: application/json" \
  -H "X-API-Key: $AMI_REGISTRY_KEY" \
  https://ami-registry.internal/api/v1/amis/latest | jq .
```

They should verify:

- Status code is 200, not 401/403/500.
- JSON exactly matches the docs (field names, nesting, types).
- Changing headers or the key fails the way docs say it should (e.g. 401 Unauthorized).

Only once they can reliably get the right JSON in the terminal/client do they move on to Terraform. This prevents “is Terraform broken or is my API call wrong?” confusion.

***

## 3. Map API behavior to Terraform data sources

Next, you show them which Terraform primitives can represent this API interaction. For a simple GET, the `http` data source is a great fit.[^1][^3]

You walk through the docs for the HTTP provider together and identify:

- `data "http"` resource to issue the request.
- `url`, `request_headers` arguments.
- `response_body` attribute and how to `jsondecode` it into a map.[^3]

Then you implement it:

```hcl
terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "ami_registry_key" {
  type      = string
  sensitive = true
}

data "http" "latest_ami" {
  url = "https://ami-registry.internal/api/v1/amis/latest"

  request_headers = {
    Accept    = "application/json"
    X-API-Key = var.ami_registry_key
  }
}

locals {
  ami_data = jsondecode(data.http.latest_ami.response_body)
}
```

This mirrors the successful `curl` call almost 1:1, which makes learning intuitive.[^5][^3]

***

## 4. Use the API data in resources

Now they wire that into the actual AWS resources:

```hcl
resource "aws_instance" "app" {
  ami           = local.ami_data.ami_id
  instance_type = "t3.micro"

  tags = {
    Name       = "app-server"
    AMIVersion = local.ami_data.version
    AMIDate    = local.ami_data.build_date
  }
}
```

Run `terraform plan` and have them confirm:

- `ami` in the diff equals the value they saw in Postman/`curl`.
- Tags use the right version/date.

This reinforces the mental model: “Terraform data source → locals/jsondecode → resource arguments.”[^5][^1]

***

## 5. Use IDE completion as an accelerator, not source of truth

In the IDE (VS Code, JetBrains, etc.) you then show them:

- How HCL language support helps with attribute suggestions (e.g. `data "http" "..."` → IDE lists `url`, `request_headers`, `method`).
- How it suggests attributes on `aws_instance` (e.g. `ami`, `instance_type`, `tags`).

But you emphasize:

- These suggestions come from the **provider schema**, not from the REST API itself.
- The IDE cannot tell them that `X-API-Key` is required; that came from the API docs.
- If they only rely on completion, they’ll miss behavior details like auth, rate limits, or allowed values.[^6][^2]

A practical trick: have them keep the API docs on one monitor and Terraform provider docs (HTTP and AWS) on the other, using completion only to speed up typing what they already understand conceptually.[^7][^3]

***

## 6. Capture exploration as reusable tests and modules

Once it works, you show them how to harden the pattern:

- Extract the API logic into a small module, e.g. `modules/latest_ami`, that outputs `ami_id`, `version`, `build_date`.
- Use that module from multiple stacks instead of re-coding the `data "http"` block everywhere.
- Optionally, add a thin integration check in CI that calls the same API directly (via a script) to catch breaking changes early.

Example minimal module:

```hcl
# modules/latest_ami/main.tf
variable "ami_registry_key" {
  type      = string
  sensitive = true
}

data "http" "latest_ami" {
  url = "https://ami-registry.internal/api/v1/amis/latest"

  request_headers = {
    Accept    = "application/json"
    X-API-Key = var.ami_registry_key
  }
}

locals {
  ami_data = jsondecode(data.http.latest_ami.response_body)
}

output "ami_id" {
  value = local.ami_data.ami_id
}

output "version" {
  value = local.ami_data.version
}

output "build_date" {
  value = local.ami_data.build_date
}
```

Then consume it:

```hcl
module "latest_ami" {
  source          = "./modules/latest_ami"
  ami_registry_key = var.ami_registry_key
}

resource "aws_instance" "app" {
  ami           = module.latest_ami.ami_id
  instance_type = "t3.micro"
}
```

This teaches them that exploration results should become repeatable, reviewable infrastructure primitives, not just one-off experiments.[^6][^5]

***

## 7. When the API use gets more complex

You can later extend the same pattern when:

- The API needs POST/PUT or multi-step flows → introduce `external` data source with a Python/Bash helper, still starting from docs and API clients.[^8][^5]
- The API is central to your platform → show them how that evolves into a full custom Terraform provider that wraps the API cleanly, using the Terraform plugin framework.[^9][^10]

But the teaching loop stays the same:

1) Read and understand the API docs/spec.
2) Prove the call in an API client or `curl`.
3) Recreate that call with Terraform data sources.
4) Use IDE completion to wire it faster, not to guess behavior.
5) Capture the pattern in modules/tests for re-use.
<span style="display:none">[^11][^12]</span>

<div align="center">⁂</div>

[^1]: https://developer.hashicorp.com/terraform/language/data-sources

[^2]: https://www.docsie.io/blog/articles/optimising-your-api-best-practices-for-documentation/

[^3]: https://github.com/hashicorp/terraform-provider-http/blob/main/docs/data-sources/http.md

[^4]: https://requestly.com/blog/top-5-open-source-api-clients-in-2025/

[^5]: https://oneuptime.com/blog/post/2025-12-18-terraform-rest-api-calls/view

[^6]: https://www.env0.com/blog/how-to-use-terraform-providers

[^7]: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

[^8]: https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external

[^9]: https://developer.hashicorp.com/terraform/plugin/framework/providers

[^10]: https://www.speakeasy.com/blog/create-a-terraform-provider-a-guide-for-beginners

[^11]: https://www.hashicorp.com/en/blog/writing-custom-terraform-providers

[^12]: https://www.reddit.com/r/Terraform/comments/14ipw5z/how_would_you_pull_data_from_external_source_and/
