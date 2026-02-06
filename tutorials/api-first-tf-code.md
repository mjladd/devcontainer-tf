# API First TF Code

## Table of Contents

- [Mental Model First](#mental-model-first)
- [Step 1: Find the provider & resource docs](#step-1-find-the-provider--resource-docs)
- [Step 2: Map Terraform fields to the underlying API](#step-2-map-terraform-fields-to-the-underlying-api)
- [Step 3: Use Terraform CLI as your "API explorer"](#step-3-use-terraform-cli-as-your-api-explorer)
- [Step 4: Lean on IDE autocomplete](#step-4-lean-on-ide-autocomplete)
- [Step 5: Read the "forces new resource" and lifecycle notes](#step-5-read-the-forces-new-resource-and-lifecycle-notes)
- [Step 6: Use `terraform plan` as a safe dry-run API call](#step-6-use-terraform-plan-as-a-safe-dry-run-api-call)
- [Step 7: Debug using Terraform logs (API-level insight)](#step-7-debug-using-terraform-logs-api-level-insight)
- [Step 8: Understand provider versioning (critical!)](#step-8-understand-provider-versioning-critical)
- [Step 9: The Terraform API learning loop](#step-9-the-terraform-api-learning-loop)

## Mental Model First

**Terraform does NOT invent resources.**
Every Terraform resource is a **thin wrapper over an API** exposed by a cloud/service provider.

So when you’re writing:

```hcl
resource "aws_s3_bucket" "example" {
  bucket = "my-bucket"
}
```

Terraform is ultimately calling:

- AWS S3 APIs
- with IAM credentials
- using parameters defined by the AWS provider schema

Your job as a Terraform user is to learn the provider’s API surface — not Terraform syntax alone.

## Step 1: Find the provider & resource docs

1. Go to registry.terraform.io
2. Find the provider (e.g. `hashicorp/aws`)
3. Navigate to the specific resource:
   `aws_s3_bucket`

This page is effectively the authoritative list of:

- arguments
- nested blocks
- defaults
- outputs
- constraints

Key things to scan immediately:

- Required vs Optional arguments
- Deprecated fields
- Notes about behavior (“changing this forces replacement”)

## Step 2: Map Terraform fields to the underlying API

Example from the docs:

```hcl
resource "aws_s3_bucket" "example" {
  bucket = "my-bucket"
  acl    = "private"
}
```

What’s *actually happening*:

- `bucket` → S3 `CreateBucket` API parameter
- `acl` → S3 ACL configuration API
- Terraform provider:
  - translates HCL → JSON
  - calls AWS APIs
  - waits for eventual consistency

When confused by a Terraform argument:

- Search for the cloud provider API doc (e.g. AWS S3 CreateBucket)
- Compare fields → this explains weird behavior, defaults, and limits

This is how you understand *why* things break.

## Step 3: Use Terraform CLI as your “API explorer”

Terraform gives you introspection tools that are often underused.

`terraform providers schema -json`

What this gives you:

- Full machine-readable schema of:
  - all resources
  - all arguments
  - types
  - optional vs required
  - computed fields

- Pipe this into `jq`
- Search for specific resources/fields
- Use it to generate docs or internal tooling

## Step 4: Lean on IDE autocomplete

VSCode w/ TF Extension provides

- Resource name autocomplete
- Argument suggestions
- Type hints
- Deprecation warnings

Autocomplete only shows **what exists**, not:

- why you should use it
- how it behaves
- edge cases
- IAM permissions required

**Best practice rule:**

> Autocomplete answers *“what can I type?”*
> Docs answer *“should I type this?”*

You need both.

## Step 5: Read the “forces new resource” and lifecycle notes

Example:

```hcl
bucket = "my-bucket"
```

Terraform docs say:

> Changing this forces a new resource

What that means:

- Terraform will **DELETE the bucket**
- Then create a new one
- Which might:
  - fail if bucket name is global
  - destroy data

**Best practice:**

- Always read:
  - `Forces new resource`
  - `Conflicts with`
  - `Exactly one of`

These are *API constraints*, not Terraform quirks.

## Step 6: Use `terraform plan` as a safe *dry-run API call*

Think of `terraform plan` as:

> “Show me the API calls you *would* make”

Example:

```bash
terraform plan
```

Read the output carefully:

```diff
+ resource "aws_s3_bucket" "example" {
    bucket = "my-bucket"
  }
```

Key habits:

- Scan for `-/+` (destroy & recreate)
- Scan for attributes marked `(known after apply)`
- Treat `plan` as required code review material

Never apply anything you don’t understand in the plan.

## Step 7: Debug using Terraform logs (API-level insight)

When something fails mysteriously:

```bash
TF_LOG=DEBUG terraform apply
```

You’ll see:

- HTTP requests
- API endpoints
- request IDs
- error payloads

This is gold for learning:

- IAM permission gaps
- invalid parameters
- provider bugs

You’re literally watching Terraform talk to the API.

## Step 8: Understand provider versioning (critical!)

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

Why this matters:

- Providers change API mappings
- Fields get deprecated
- Defaults change
- New resources appear

**Best practice:**

- Pin provider versions
- Read provider changelogs before upgrading
- Upgrade in isolation, not bundled with infra changes

## Step 9: The Terraform API learning loop

1. Identify the resource you need
2. Read the Terraform Registry doc
3. Skim underlying cloud API doc if behavior is unclear
4. Use IDE autocomplete to scaffold
5. Run `terraform plan`
6. Inspect diffs and lifecycle notes
7. Apply in sandbox
8. Read logs if it fails
9. Write comments explaining *why*, not *what*

> “Terraform isn’t magic.
> It’s a strongly-typed, versioned client for someone else’s API.
> If you understand the API, Terraform becomes predictable.”
